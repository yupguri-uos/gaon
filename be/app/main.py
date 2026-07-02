from fastapi import FastAPI

from app.routers import documents, auth

app = FastAPI(title="GAON API")

app.include_router(documents.router)
app.include_router(auth.router, prefix = "/auth", tags=["Auth"])


@app.get("/health")
def health() -> dict:
    return {"ok": True}
