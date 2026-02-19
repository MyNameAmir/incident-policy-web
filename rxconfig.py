import reflex as rx

config = rx.Config(
    app_name="incident_policy_web",
    plugins=[
        rx.plugins.SitemapPlugin(),
        rx.plugins.TailwindV4Plugin(),
    ]
)