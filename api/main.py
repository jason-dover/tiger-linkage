from typing import List
from fastapi import FastAPI
from pydantic import BaseModel


class TigerlinkRequest(BaseModel):
    data: List[float]


class TigerlinkResponse(BaseModel):
    data: List[float]


app = FastAPI()

@app.post("/identify", response_model=TigerlinkResponse)
def identify(input: TigerlinkRequest):
    return TigerlinkResponse(data=[1.8])
