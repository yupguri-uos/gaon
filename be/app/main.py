from fastapi import FastAPI

from app.routers import documents

app = FastAPI(title="GAON API")

app.include_router(documents.router)


@app.get("/health")
def health() -> dict:
    return {"ok": True}
