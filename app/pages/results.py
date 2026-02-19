import reflex as rx
from app.state import AppState


def decision_css():
    # pulse animation for the icon badge
    return rx.html("""
    <style>
      @keyframes pulse {
        0% { transform: scale(1); opacity: 1; }
        50% { transform: scale(1.05); opacity: 0.92; }
        100% { transform: scale(1); opacity: 1; }
      }
    </style>
    """)


def decision_hero():
    return rx.cond(
        AppState.decision == "Violation",
        rx.card(
            rx.hstack(
                rx.box(
                    "✖",
                    font_size="52px",
                    color="white",
                    padding="14px 18px",
                    border_radius="18px",
                    style={
                        "background": "linear-gradient(135deg, #ef4444, #b91c1c)",
                        "animation": "pulse 1.2s ease-in-out infinite",
                    },
                ),
                rx.vstack(
                    rx.heading("Violation Detected", size="6", color="#7f1d1d"),
                    rx.text(
                        "The incident is supported by at least one policy rule in the retrieved evidence.",
                        color_scheme="gray",
                    ),
                    spacing="1",
                    align="start",
                ),
                spacing="4",
                align="center",
            ),
            width="100%",
            border_radius="22px",
            style={"boxShadow": "0 14px 40px rgba(239,68,68,0.18)"},
        ),
        rx.cond(
            AppState.decision == "No violation",
            rx.card(
                rx.hstack(
                    rx.box(
                        "✓",
                        font_size="52px",
                        color="white",
                        padding="14px 18px",
                        border_radius="18px",
                        style={
                            "background": "linear-gradient(135deg, #22c55e, #15803d)",
                            "animation": "pulse 1.6s ease-in-out infinite",
                        },
                    ),
                    rx.vstack(
                        rx.heading("No Violation Found", size="6", color="#14532d"),
                        rx.text(
                            "No policy-backed violation was found based on the retrieved evidence.",
                            color_scheme="gray",
                        ),
                        spacing="1",
                        align="start",
                    ),
                    spacing="4",
                    align="center",
                ),
                width="100%",
                border_radius="22px",
                style={"boxShadow": "0 14px 40px rgba(34,197,94,0.16)"},
            ),
            rx.card(
                rx.hstack(
                    rx.box(
                        "!",
                        font_size="52px",
                        color="white",
                        padding="14px 18px",
                        border_radius="18px",
                        style={
                            "background": "linear-gradient(135deg, #64748b, #334155)",
                            "animation": "pulse 1.8s ease-in-out infinite",
                        },
                    ),
                    rx.vstack(
                        rx.heading("Not Enough Policy Evidence", size="6", color="#0f172a"),
                        rx.text(
                            "The retrieved policy excerpts do not contain an exact rule that matches the incident.",
                            color_scheme="gray",
                        ),
                        spacing="1",
                        align="start",
                    ),
                    spacing="4",
                    align="center",
                ),
                width="100%",
                border_radius="22px",
                style={"boxShadow": "0 14px 40px rgba(100,116,139,0.14)"},
            ),
        ),
    )


def results_page():
    # Build up to 10 cards (older Reflex compatible, avoids foreach typing issues)
    chunk_cards = []
    for i in range(10):
        chunk_cards.append(
            rx.cond(
                i < AppState.top_chunks.length(),
                rx.card(
                    rx.vstack(
                        rx.hstack(
                            rx.badge(f"Rank {i+1}", variant="soft"),
                            rx.spacer(),
                            rx.text("Score: " + AppState.top_chunks[i]["score"], color_scheme="gray", font_size="2"),
                            width="100%",
                        ),
                        rx.text(AppState.top_chunks[i]["chunk"], white_space="pre-wrap"),
                        spacing="2",
                        align="start",
                    ),
                    width="100%",
                    border_radius="18px",
                    style={"boxShadow": "0 10px 25px rgba(0,0,0,0.08)"},
                ),
                rx.fragment(),
            )
        )

    return rx.center(
        rx.vstack(
            decision_css(),

            rx.hstack(
                rx.button("← New Analysis", on_click=rx.redirect("/"), variant="soft"),
                rx.spacer(),
                rx.badge(AppState.decision, variant="soft", color_scheme="teal"),
                width="100%",
            ),

            rx.heading("Results", size="8", color="#0f766e"),

            decision_hero(),

            rx.card(
                rx.vstack(
                    rx.hstack(
                        rx.icon("file_search", size=22),
                        rx.vstack(
                            rx.text("Final Decision Report", weight="bold"),
                            rx.text("Generated from retrieved policy evidence.", color_scheme="gray", font_size="2"),
                            spacing="0",
                            align="start",
                        ),
                        spacing="2",
                        align="center",
                    ),
                    rx.divider(),
                    rx.text(AppState.report_text, white_space="pre-wrap"),
                    spacing="3",
                    align="stretch",
                ),
                width="100%",
                border_radius="22px",
                style={"boxShadow": "0 14px 40px rgba(0,0,0,0.10)"},
            ),

            rx.button(
                rx.cond(
                    AppState.show_chunks,
                    "Hide Policy Evidence",
                    "Show Policy Evidence (Top 10 Chunks)",
                ),
                on_click=AppState.toggle_chunks,
                variant="soft",
                color_scheme="teal",
                width="320px",
            ),

            rx.cond(
                AppState.show_chunks,
                rx.vstack(
                    rx.heading("Top 10 Most Related Policy Chunks", size="5"),
                    rx.text("These are the top retrieved excerpts used as evidence.", color_scheme="gray"),
                    rx.vstack(*chunk_cards, spacing="3", width="100%"),
                    spacing="3",
                    width="100%",
                ),
            ),

            width="min(980px, 92vw)",
            spacing="5",
            padding_y="40px",
            align="stretch",
        )
    )
