FROM python:3.8-slim-buster
LABEL maintainer="Jason Dover <jason.roka@gmail.com>"

ENV MODULE_NAME="main"

RUN python -m pip install --upgrade pip

COPY . .

RUN pip install -r requirements.txt

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
