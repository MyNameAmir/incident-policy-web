# agent/policy_agent_file_search.py
#
# FINAL STABLE VERSION (Prompt ONLY improved — NO keywords, NO extra LLM calls)
# - Uses OpenAI vector stores search
# - No manual embeddings
# - No keyword bias
# - Clean chunk display
# - Multi-violation structured evaluation
# - Cached vector store by SHA256
#
# Only change vs your last code:
# ✅ replace the prompt in evaluate_incident() with a stronger one that:
#   - forces "one unique quote per violation"
#   - forces each quote to be a real rule sentence (not definitions/examples/background)
#   - forces using incident facts (short copied phrases) so it can’t drift
#   - forbids inventing duties (e.g., notification) unless explicitly stated
#   - prevents duplicates / near-duplicates
#   - allows “Not enough policy evidence” for parts that aren’t proven

import os
import json
import hashlib
import re
from typing import List, Tuple, Optional, Dict
import math
from dotenv import load_dotenv
from openai import OpenAI
from PyPDF2 import PdfReader
import nltk
MAX_QUERY_CHARS = 4096
# --------------------------------------------------
# Setup
# --------------------------------------------------

load_dotenv()
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

MODEL = "gpt-4o-mini"

CACHE_DIR = "cache"
CACHE_FILE = os.path.join(CACHE_DIR, "vector_store_cache.json")


# --------------------------------------------------
# Utilities
# --------------------------------------------------

def ensure_nltk_punkt():
    """
    Ensure all required NLTK sentence tokenizer resources are installed.
    Required for nltk>=3.8 which separates punkt and punkt_tab.
    """
    resources = [
        "tokenizers/punkt",
        "tokenizers/punkt_tab/english",
    ]

    for resource in resources:
        try:
            nltk.data.find(resource)
        except LookupError:
            if "punkt_tab" in resource:
                nltk.download("punkt_tab", quiet=True)
            else:
                nltk.download("punkt", quiet=True)

def sentence_chunks_adaptive(
    text: str,
    target_queries: int = 8,
    min_sentences: int = 4,
    max_sentences_cap: int = 14,
    overlap_ratio: float = 0.25,   # 25% of chunk sentences as overlap
    max_query_chars: int = MAX_QUERY_CHARS,
) -> List[str]:
    """
    Adaptive sentence chunking:
    - Chooses max_sentences so total chunks ~ target_queries
    - Chooses overlap as a fraction of chunk size (bounded)
    - Enforces max_query_chars
    - No summarization, no keywords, no extra LLM calls
    """
    if not text:
        return []

    ensure_nltk_punkt()
    text = normalize_text(text)

    from nltk.tokenize import sent_tokenize
    sents = [s.strip() for s in sent_tokenize(text) if s.strip()]
    if not sents:
        return [text[:max_query_chars].strip()] if text.strip() else []

    n = len(sents)

    # Choose chunk sentence count so that #chunks ≈ target_queries
    # chunks ≈ ceil(n / step), step = max_sentences - overlap
    # We'll start by aiming for step ≈ ceil(n / target_queries)
    step_target = max(1, math.ceil(n / max(1, target_queries)))

    # pick max_sentences around step_target + overlap; start with overlap computed from ratio
    max_sentences = int(round(step_target / max(1e-6, (1 - overlap_ratio))))
    max_sentences = max(min_sentences, min(max_sentences, max_sentences_cap))

    overlap = int(round(max_sentences * overlap_ratio))
    overlap = max(1, min(overlap, 4))  # keep overlap modest (1–4 sentences)

    step = max(1, max_sentences - overlap)

    chunks: List[str] = []
    i = 0
    while i < n:
        chunk_sents = sents[i:i + max_sentences]
        chunk = " ".join(chunk_sents).strip()

        # Enforce max_query_chars:
        # If too long, shrink by dropping sentences from the end until it fits.
        if len(chunk) > max_query_chars:
            j = len(chunk_sents)
            while j > 1:
                j -= 1
                chunk = " ".join(chunk_sents[:j]).strip()
                if len(chunk) <= max_query_chars:
                    break
            if len(chunk) > max_query_chars:
                chunk = chunk[:max_query_chars].strip()

        if chunk:
            chunks.append(chunk)

        i += step

    return chunks




def split_into_sentences_nltk(text: str) -> List[str]:
    import nltk
    try:
        from nltk.tokenize import sent_tokenize
    except Exception:
        raise

    # If punkt isn't installed, this will throw LookupError
    try:
        sents = sent_tokenize(text)
    except LookupError:
        nltk.download("punkt")
        sents = sent_tokenize(text)

    return [s.strip() for s in sents if s.strip()]



def ensure_cache_dir():
    os.makedirs(CACHE_DIR, exist_ok=True)


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def load_cache():
    if not os.path.exists(CACHE_FILE):
        return {}
    with open(CACHE_FILE, "r") as f:
        return json.load(f)


def save_cache(data):
    ensure_cache_dir()
    with open(CACHE_FILE, "w") as f:
        json.dump(data, f, indent=2)


def read_pdf_text(path: str) -> str:
    parts = []
    with open(path, "rb") as f:
        reader = PdfReader(f)
        for page in reader.pages:
            t = page.extract_text() or ""
            if t.strip():
                parts.append(t)
    return "\n".join(parts)


def normalize_text(text: str) -> str:
    # Fix Windows line breaks and PDF artifacts
    text = text.replace("\r", " ")
    text = text.replace("\n", " ")
    text = text.replace("\xa0", " ")
    text = re.sub(r"\(cid:\d+\)", " ", text)
    text = re.sub(r"\s{2,}", " ", text)
    return text.strip()


#might be extra and unnecessary
def dedupe_chunks(chunks: List[Tuple[float, str]]) -> List[Tuple[float, str]]:
    """
    Minimal stability improvement:
    - policies often repeat the same paragraph
    - de-duping reduces repeated violations and repeated evidence
    - NO keywords; just exact/near-exact duplicate removal
    """
    seen = set()
    out: List[Tuple[float, str]] = []
    for score, txt in chunks:
        key = re.sub(r"\s+", " ", txt).strip().lower()
        if key in seen:
            continue
        seen.add(key)
        out.append((score, txt))
    return out


# --------------------------------------------------
# Vector Store
# --------------------------------------------------

def get_or_create_vector_store(policy_pdf_path: str) -> str:
    file_hash = sha256_file(policy_pdf_path)
    cache = load_cache()

    if file_hash in cache:
        cached_value = cache[file_hash]
        if isinstance(cached_value, dict):
            return cached_value.get("vector_store_id")
        return cached_value

    vs = client.vector_stores.create(
        name=f"policy-{file_hash[:10]}"
    )

    with open(policy_pdf_path, "rb") as f:
        client.vector_stores.files.upload_and_poll(
            vector_store_id=vs.id,
            file=f,
        )

    cache[file_hash] = vs.id
    save_cache(cache)

    return vs.id


# --------------------------------------------------
# Retrieval (Pure semantic, no keywords)
# --------------------------------------------------

def retrieve_top_chunks(
    vector_store_id: str,
    incident_text: str,
    top_k: int = 8,
    target_queries: int = 8,
    per_query_k: int = 6,
) -> List[Tuple[float, str]]:
    # 1) Make multiple sentence-based queries (adaptive, bounded)
    queries = sentence_chunks_adaptive(
        incident_text,
        target_queries=target_queries,
        max_query_chars=MAX_QUERY_CHARS,
    )

    print(f"[retrieve_top_chunks] Generated {len(queries)} query chunks from incident.")
    if not queries:
        return []

    # 2) Run vector search per query and merge results
    best: Dict[str, Tuple[float, str]] = {}  # normalized_text -> (best_score, original_text)

    for q in queries:
        q = q[:MAX_QUERY_CHARS].strip()
        if not q:
            continue

        results = client.vector_stores.search(
            vector_store_id=vector_store_id,
            query=q,
            max_num_results=per_query_k,
        )

        for item in results.data:
            if not item.content:
                continue

            score = float(item.score)
            text = normalize_text(item.content[0].text)

            # normalize for dedupe key
            key = re.sub(r"\s+", " ", text).strip().lower()

            prev = best.get(key)
            if prev is None or score > prev[0]:
                best[key] = (score, text)

    merged = list(best.values())
    merged.sort(key=lambda x: x[0], reverse=True)

    # 3) Your existing deduper (extra safety)
    #merged = dedupe_chunks(merged)

    # 4) Return top_k overall
    return merged[:top_k]

def polish_and_group_violations(final_eval_text: str) -> str:
    """
    Post-processor agent (chunk-aware):
    - Groups duplicates under minimal parents
    - NEVER drops or edits chunk citations like [Chunk 3]
    - Evidence lines must remain verbatim INCLUDING chunk tags
    """

    prompt = f"""
You are a *polishing / structuring agent*.

You will be given an evaluation text that includes Evidence lines formatted like:
  - [Chunk <#>] "..."

CRITICAL IMMUTABLE RULE:
- The substring [Chunk <#>] is REQUIRED metadata and MUST be preserved EXACTLY.
- You must copy Evidence lines verbatim INCLUDING the [Chunk <#>] prefix and the quoted sentence.
- Do not remove it. Do not move it outside the Evidence bullet. Do not renumber it.

ABSOLUTE REQUIREMENTS:
1) DO NOT remove any incidents. Ever.
2) Minimize the number of parent groups by merging semantically equivalent parents.
3) Duplicates MUST be grouped:
   - If Evidence sentence meaning is the same, merge.
4) When merging parents:
   - Choose ONE best parent title (≤ 8 words).
   - Choose ONE primary Evidence line EXACTLY as written, including its [Chunk #].
   - Combine all children under that parent and renumber A1, A2, ...
   - If the other parent has a truly distinct rule, include it under:
     - Additional evidence:
       - [Chunk #] "..."
     again copied verbatim INCLUDING chunk tags.
5) Do NOT invent new evidence or new chunk numbers.
6) Do NOT rewrite quoted policy sentences.
7) Keep each child’s Incident fact verbatim.
8) Keep Why to 1 sentence (may shorten but not change meaning).

OUTPUT FORMAT (exact):

Decision: <Violation | No violation | Not enough policy evidence>

If Violation:
A) <Parent short title (max 8 words)>
- Evidence:
  - [Chunk <#>] "<one exact policy sentence>"
- Additional evidence: (optional; only if truly distinct)
  - [Chunk <#>] "<one exact policy sentence>"
- Children:
  - A1) Incident fact: "<...>"
       Why: <...>
  - A2) ...

B) ... (only if truly distinct)

If No violation:
- Why: <1–2 sentences>
- Evidence:
  - [Chunk <#>] "<one exact sentence that permits it>"
- Incident fact:
  - "<copy 3–12 words from incident>"

If Not enough policy evidence:
- Reason: <1–2 sentences>

FINAL MERGE CHECK:
- If any two parents can be merged without losing meaning, merge them.

HERE IS THE TEXT TO POLISH:
{final_eval_text}
""".strip()

    response = client.responses.create(
        model=MODEL,
        input=prompt,
        temperature=0,
    )

    return response.output_text.strip()
# --------------------------------------------------
# Evaluation (Prompt ONLY improved)
# --------------------------------------------------
def evaluate_incident(
    top_chunks: List[Tuple[float, str]],
    incident_text: str
) -> str:
    """
    Evaluator with chunk-aware evidence citations.
    - Adds chunk number(s) for each Evidence / Additional evidence sentence.
    - Still: pure semantic (no keyword heuristics), minimal parent grouping, full action coverage.
    """

    if not top_chunks:
        return "Decision: Not enough policy evidence\nReason: No policy excerpts retrieved."

    policy_text = "\n\n".join(
        f"[Chunk {i+1}]\n{chunk}"
        for i, (_, chunk) in enumerate(top_chunks)
    )

    prompt = f"""
You are evaluating an incident against policy text.

Incident:
{incident_text}

Policy Excerpts (ONLY evidence source):
{policy_text}

CORE CONSTRAINTS (do not violate):
1) Use ONLY the Policy Excerpts above. No outside knowledge. No assumptions.

2) FIRST extract ALL distinct incident actions from the Incident text.
   An incident action is any separate act involving access, use, disclosure,
   copying, transmission, storage, or notification involving personal health information.

3) You MUST account for EVERY incident action extracted in step (2).
   Each action must be either:
   (a) included as a Child under a Violation, OR
   (b) listed under a section titled "Unmapped incident actions" with reason:
       "Not enough policy evidence."

4) You are NOT allowed to omit any incident action.

5) List EVERY DISTINCT violation separately (do NOT merge unrelated violations).

6) Each violation must include exactly ONE quoted policy sentence as Evidence.

7) The Evidence sentence must be copied EXACTLY from the excerpts (verbatim).

8) Do NOT reuse the same Evidence sentence for multiple violations unless it genuinely applies.

9) Evidence must be a RULE sentence (requirement, prohibition, or safeguard obligation).
   Do NOT use definitions, examples, explanations, or headings.

10) Your "Why" must reference concrete incident facts by copying 3–12 words from the incident.

11) If policy evidence is broad (e.g., safeguard requirement), you MUST still include the child action under that violation rather than omitting it.

MANDATORY:
- For EACH evidence sentence you cite, you MUST also cite the chunk number it came from.
- If the exact sentence appears in multiple chunks, pick the SINGLE best chunk number and cite only that.

OUTPUT FORMAT (exact):

Decision: <Violation | No violation | Not enough policy evidence>

If Violation:
A) <Parent short title (max 8 words)>
- Evidence:
  - [Chunk <#>] "<one exact policy sentence>"
- Additional evidence: (optional; include ONLY if needed; otherwise omit)
  - [Chunk <#>] "<one exact policy sentence>"
  - [Chunk <#>] "<one exact policy sentence>"
- Children:
  - A1) Incident fact: "<copy 3–12 words verbatim from incident>"
       Why: <1 sentence linking that fact to Evidence or Additional evidence>
  - A2) ...

B) <Next parent (ONLY if truly distinct from A)>
- Evidence:
  - [Chunk <#>] "<one exact policy sentence>"
- Children:
  - B1) ...

If No violation:
- Why: <1–2 sentences>
- Evidence:
  - [Chunk <#>] "<one exact RULE sentence that explicitly permits it>"
- Incident fact:
  - "<copy 3–12 words verbatim from incident>"

If Not enough policy evidence:
- Reason: <1–2 sentences explaining what is missing from excerpts>

SELF-CHECK:
- Chunk citation: every quoted evidence line has exactly one [Chunk #].
- Coverage: every distinct incident action appears as a child.
- Redundancy: merge duplicate parents.
""".strip()

    response = client.responses.create(
        model=MODEL,
        input=prompt,
        temperature=0,
    )

    return response.output_text.strip()

    
def augment_missing_children_from_incident(
    incident_text: str,
    current_eval_text: str,
) -> str:
    """
    Augmentation agent:
    - Input: incident_text + current evaluation text (already produced by evaluate_incident or by a prior step)
    - Output: same format, but with any *missing* child incidents added under existing parents
      when the parent Evidence already covers the behavior.

    This does NOT require new policy quotes, so it works even when the policy excerpts
    don’t contain a perfect standalone 'rule sentence' for the missed issue.

    Hard guarantees:
    - Never remove or rewrite existing parents/children (only ADD).
    - Every added child must quote 3–12 words verbatim from the incident_text.
    - Added children must fit under an existing parent’s Evidence (no inventing new rule coverage).
    """

    prompt = f"""
You are an augmentation agent.

You will be given:
(1) Incident text
(2) An existing evaluation output that contains parent violations with Evidence and Children.

Your task:
- ADD missing child incidents that are clearly present in the Incident text but not represented
  as any existing child "Incident fact" in the evaluation.
- Only add children that fall under an EXISTING parent’s Evidence (do not create new parents here).
- Do NOT delete anything. Do NOT merge anything. Do NOT rename parents.
- Preserve the exact evaluation output and ONLY insert new children where needed.

What counts as "missing"?
- A distinct action/event in the incident (e.g., overheard disclosure in public area)
  that is not already captured by an existing child incident fact.

Rules:
1) Never remove or modify existing text; only add new children lines.
2) Each new child must include:
   - Incident fact: must be copied verbatim (3–12 words) from the incident text.
   - Why: 1 sentence linking to the parent Evidence.
3) If the incident includes multiple disclosure channels (talking aloud + public overhearing),
   they should become separate children.
4) Ensure numbering continues correctly under each parent (A3, A4, etc.).

Return the full revised evaluation in the SAME format as input.

INCIDENT TEXT:
{incident_text}

CURRENT EVALUATION:
{current_eval_text}
""".strip()

    response = client.responses.create(
        model=MODEL,
        input=prompt,
        temperature=0,
    )

    return response.output_text.strip()

# --------------------------------------------------
# Main Runner
# --------------------------------------------------

def run_analysis(policy_pdf: str, incident_pdf: str):

    incident_raw = read_pdf_text(incident_pdf)
    incident_text = normalize_text(incident_raw)

    # Remove template boilerplate if exists
    incident_text = re.sub(
        r"Purpose of Evaluation:.*",
        "",
        incident_text,
        flags=re.IGNORECASE
    ).strip()

    print("\n" + "="*90)
    print("INCIDENT")
    print("="*90)
    print(incident_text)

    vs_id = get_or_create_vector_store(policy_pdf)
    print(f"\nUsing vector store: {vs_id}")

    top_chunks = retrieve_top_chunks(vs_id, incident_text, top_k=8)

    print("\n" + "="*90)
    print("TOP MATCHED POLICY CHUNKS")
    print("="*90)

    for i, (score, text) in enumerate(top_chunks, 1):
        print(f"\nRank {i} | Score: {round(score, 4)}")
        print("-"*90)
        print(text)

    result = evaluate_incident(top_chunks, incident_text)
    #result = augment_missing_children_from_incident(incident_text, result)
    result = polish_and_group_violations(result)
    print("\n" + "="*90)
    print("FINAL INCIDENT EVALUATION")
    print("="*90)
    print(result)
    print("="*90)


# test:
# from embedding_store import run_analysis
# POLICY_PDF = "files/policy3.pdf"
# INCIDENT_PDF = "files/incident13.pdf"
# run_analysis(POLICY_PDF, INCIDENT_PDF)
