from fastapi import FastAPI

from app.routers import calendar, documents, onboarding, profile

app = FastAPI(title="GAON API")

app.include_router(documents.router)
app.include_router(onboarding.router)
app.include_router(calendar.router)
app.include_router(profile.router)


@app.get("/health")
def health() -> dict:
    return {"ok": True}
