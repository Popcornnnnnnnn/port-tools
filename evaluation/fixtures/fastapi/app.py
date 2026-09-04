from fastapi import FastAPI


app = FastAPI(title="port-tools FastAPI fixture")


@app.get("/")
def root() -> dict:
    return {"fixture": "port-tools", "framework": "fastapi", "status": "healthy"}


@app.get("/events")
def events() -> dict:
    return {"transport": "http", "streaming_fixture": "pending-route-spike"}
