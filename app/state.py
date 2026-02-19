import os
import uuid
from typing import Optional, List, Dict

import reflex as rx

from agent.embedding_store import (
    get_or_create_vector_store,
    retrieve_top_chunks,
    evaluate_incident,
    read_pdf_text,
    normalize_text,
    polish_and_group_violations,
)

UPLOAD_DIR = "uploads"


class AppState(rx.State):
    # Saved file paths (server-side)
    policy_path: Optional[str] = None
    incident_path: Optional[str] = None

    # UI status
    error: str = ""
    is_running: bool = False

    # Results (keep types simple and consistent)
    top_chunks: List[Dict[str, str]] = []   # [{"score":"0.1234", "chunk":"..."}]
    decision: str = ""
    report_text: str = ""

    # UI toggle
    show_chunks: bool = False

    def toggle_chunks(self):
        self.show_chunks = not self.show_chunks

    def _save_upload_bytes(self, original_name: str, data: bytes) -> str:
        os.makedirs(UPLOAD_DIR, exist_ok=True)
        safe_name = f"{uuid.uuid4().hex}_{original_name}".replace(" ", "_")
        path = os.path.join(UPLOAD_DIR, safe_name)
        with open(path, "wb") as f:
            f.write(data)
        return path

    # Upload handlers (Reflex upload_files -> this handler)
    async def handle_policy_upload(self, files: List[rx.UploadFile]):
        self.error = ""
        if not files:
            self.error = "No policy file received."
            return
        f = files[0]
        data = await f.read()
        self.policy_path = self._save_upload_bytes(f.filename, data)

    async def handle_incident_upload(self, files: List[rx.UploadFile]):
        self.error = ""
        if not files:
            self.error = "No incident file received."
            return
        f = files[0]
        data = await f.read()
        self.incident_path = self._save_upload_bytes(f.filename, data)

    @rx.event(background=True)
    async def run_agent(self):
        # Start: update UI immediately
        async with self:
            self.error = ""
            self.is_running = True
            self.show_chunks = False
            self.top_chunks = []
            self.decision = ""
            self.report_text = ""

            if not self.policy_path or not self.incident_path:
                self.error = "Please upload BOTH Policy PDF and Incident PDF."
                self.is_running = False
                return

        # Heavy work outside lock
        try:# Build incident text
            incident_raw = read_pdf_text(self.incident_path)
            incident_text = normalize_text(incident_raw)

            # Create / load vector store for the policy
            vs_id = get_or_create_vector_store(self.policy_path)

            # Retrieve chunks (your function returns List[Tuple[score, text]])
            retrieved = retrieve_top_chunks(
                vector_store_id=vs_id,
                incident_text=incident_text,
                top_k=25,
                target_queries=8,
                per_query_k=6,
            )

            # Show top 10 in UI
            top10 = []
            for score, chunk_text in retrieved[:10]:
                top10.append({"score": f"{float(score):.4f}", "chunk": str(chunk_text)})

            # Evaluate (your evaluator expects the same retrieved list + incident_text)
            report = evaluate_incident(retrieved, incident_text)

            # Optional (you already do it in run_analysis; keep if you want same output)
            report = polish_and_group_violations(report)
            if "Decision: Violation" in report:
                decision = "Violation"
            elif "Decision: No violation" in report:
                decision = "No violation"
            else:
                decision = "Not enough policy evidence"

            # Save results back to state
            async with self:
                self.top_chunks = top10
                self.report_text = report
                self.decision = decision
                self.is_running = False

            # Navigate after finishing
            yield rx.redirect("/results")

        except Exception as e:
            async with self:
                self.error = f"Error while analyzing: {e}"
                self.is_running = False
