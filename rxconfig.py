import reflex as rx

config = rx.Config(
    app_name="incident_policy_web",
    allowed_hosts=[
        "incident-policy-web.onrender.com",
        "localhost",
        "127.0.0.1",
    ],
    plugins=[
        rx.plugins.SitemapPlugin(),
        rx.plugins.TailwindV4Plugin(),
    ],
)
