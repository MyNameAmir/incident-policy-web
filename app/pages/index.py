import reflex as rx
from app.state import AppState


def hero_section():
    return rx.box(
        rx.center(
            rx.vstack(
                # rx.hstack(
                #     rx.badge("Biomedical Engineering", variant="soft", color_scheme="teal"),
                #     rx.badge("Policy–Incident RAG", variant="soft", color_scheme="blue"),
                #     spacing="2",
                #     justify="center",
                #     wrap="wrap",
                #     width="100%",
                # ),
                rx.heading(
                    "Hospital Policy & Incident Compliance Checker",
                    size="9",
                    text_align="center",
                ),
                rx.text(
                    "Upload a hospital policy PDF and an incident report. "
                    "The agent retrieves the most relevant policy evidence and evaluates whether a violation occurred.",
                    text_align="center",
                    color="#334155",
                    max_width="820px",
                    font_size="4",
                ),
                # rx.hstack(
                #     rx.badge("Evidence-first", variant="soft"),
                #     rx.badge("Top policy chunks", variant="soft"),
                #     rx.badge("Clear decision report", variant="soft"),
                #     spacing="2",
                #     justify="center",
                #     wrap="wrap",
                #     width="100%",
                # ),
                rx.image(
                    src="https://img.freepik.com/free-vector/people-walking-sitting-hospital-building-city-clinic-glass-exterior-flat-vector-illustration-medical-help-emergency-architecture-healthcare-concept_74855-10130.jpg",
                    width="100%",
                    max_width="980px",
                    height="auto",
                    #object_fit="cover",
                    border_radius="24px",
                    style={"boxShadow": "0 14px 40px rgba(0,0,0,0.14)"},
                ),
                spacing="4",
                align="center",
                width="100%",
            ),
            width="100%",
        ),
        width="100%",
        padding_y="44px",
        padding_x="18px",
        style={
            "background": "linear-gradient(135deg, rgba(20,184,166,0.14), rgba(59,130,246,0.10), rgba(255,255,255,1))"
        },
    )


def upload_panel(title: str, subtitle: str, upload_id: str, upload_handler, saved_cond):
    return rx.card(
        rx.vstack(
            rx.hstack(
                rx.icon("file_text", size=22),
                rx.vstack(
                    rx.heading(title, size="4"),
                    rx.text(subtitle, color_scheme="gray", font_size="2"),
                    spacing="0",
                    align="start",
                ),
                spacing="2",
                align="center",
                width="100%",
            ),

            rx.upload(
                rx.vstack(
                    rx.button("Choose PDF", width="100%", color_scheme="teal"),
                    rx.text("Selected: ", rx.selected_files(upload_id), color_scheme="gray", font_size="2"),
                    spacing="2",
                    width="100%",
                ),
                id=upload_id,
                accept={"application/pdf": [".pdf"]},
                max_files=1,
                border="2px dashed #94a3b8",
                padding="16px",
                width="100%",
                border_radius="16px",
            ),

            rx.hstack(
                rx.button(
                    "Upload",
                    on_click=upload_handler(rx.upload_files(upload_id)),
                    variant="soft",
                    color_scheme="teal",
                    width="100%",
                ),
                rx.button(
                    "Clear",
                    on_click=rx.clear_selected_files(upload_id),
                    variant="ghost",
                    width="100%",
                ),
                spacing="2",
                width="100%",
            ),

            rx.cond(
                saved_cond,
                rx.callout(
                    "Saved on server.",
                    icon="check_circle",
                    color_scheme="green",
                    variant="soft",
                    width="100%",
                ),
            ),

            spacing="3",
            align="stretch",
        ),
        width="100%",
        border_radius="22px",
        style={"boxShadow": "0 10px 25px rgba(0,0,0,0.08)"},
    )


def analyzing_panel():
    return rx.card(
        rx.hstack(
            rx.spinner(size="3"),
            rx.vstack(
                rx.heading("Analyzing documents…", size="4"),
                rx.text(
                    "Embedding policy chunks → retrieving evidence → evaluating violations. "
                    "This can take 30–90 seconds depending on PDF length.",
                    color_scheme="gray",
                    font_size="2",
                    max_width="760px",
                ),
                spacing="1",
                align="start",
            ),
            spacing="3",
            align="center",
        ),
        width="100%",
        border_radius="18px",
        style={"boxShadow": "0 10px 25px rgba(0,0,0,0.08)"},
    )


def index_page():
    return rx.vstack(
        hero_section(),

        rx.center(
            rx.vstack(
                rx.cond(
                    AppState.error != "",
                    rx.callout(
                        AppState.error,
                        icon="triangle_alert",
                        color_scheme="red",
                        variant="soft",
                        width="100%",
                    ),
                ),

                rx.grid(
                    upload_panel(
                        "Upload Hospital Policy (PDF)",
                        "Examples: PHIPA, hospital privacy policy, staff conduct rules.",
                        "policy_upload",
                        AppState.handle_policy_upload,
                        AppState.policy_path != None,
                    ),
                    upload_panel(
                        "Upload Incident Report (PDF)",
                        "A report describing what happened (staff actions, disclosure, access, etc.).",
                        "incident_upload",
                        AppState.handle_incident_upload,
                        AppState.incident_path != None,
                    ),
                    columns=rx.breakpoints(initial="1", md="2"),
                    spacing="4",
                    width="100%",
                ),

                rx.button(
                    rx.cond(AppState.is_running, "Analyzing…", "Analyze Incident"),
                    on_click=AppState.run_agent,
                    disabled=AppState.is_running,
                    size="3",
                    color_scheme="teal",
                    width="320px",
                    style={"boxShadow": "0 10px 25px rgba(20,184,166,0.20)"},
                ),

                rx.cond(AppState.is_running, analyzing_panel()),

                # rx.text(
                #     "Tip: If you test the same policy multiple times, caching makes future analyses faster.",
                #     color_scheme="gray",
                #     font_size="2",
                #     text_align="center",
                # ),

                width="min(980px, 92vw)",
                spacing="5",
                padding_y="40px",
                align="stretch",
            )
        )
    )
