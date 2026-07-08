from fastapi import FastAPI

from app.routers import (
    auth,
    calendar,
    children,
    documents,
    onboarding,
    profile,
    report,
    teacher_message,
)

app = FastAPI(title="GAON API")

app.include_router(documents.router)
app.include_router(onboarding.router)
app.include_router(calendar.router)
app.include_router(profile.router)
app.include_router(children.router)
app.include_router(teacher_message.router)
app.include_router(report.router)
app.include_router(auth.router, prefix="/auth", tags=["Auth"])


@app.get("/health")
def health() -> dict:
    return {"ok": True}
