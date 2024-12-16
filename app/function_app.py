import logging
import azure.functions as func
from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
import openai
import os
import json

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.function_name("IngestFile")
@app.route(methods=["POST"])
@app.embeddings_store_output(arg_name="requests", input= "{Text}", input_type="rawtext", connection_name="AZURE_AISEARCH_ENDPOINT", collection="openai-index", model="%EMBEDDING_MODEL_DEPLOYMENT_NAME%")
def ingest_file(req: func.HttpRequest, requests: func.Out[str]) -> func.HttpResponse:
    user_message = req.get_json()
    if not user_message:
        return func.HttpResponse(json.dumps({"message": "No message provided"}), status_code=400, mimetype="application/json")
    requests.set(json.dumps(user_message))
    response_json = {
        "status": "success",
        "title": user_message.get("Title"),
        "text": user_message.get("Text")
    }
    return func.HttpResponse(json.dumps(response_json), status_code=200, mimetype="application/json")


@app.function_name("PromptFile")
@app.route(methods=["POST"])
@app.semantic_search_input(arg_name="result", connection_name="AZURE_AISEARCH_ENDPOINT", collection="openai-index", query="{question}", embeddings_model="%EMBEDDING_MODEL_DEPLOYMENT_NAME%", chat_model="%CHAT_MODEL_DEPLOYMENT_NAME%")
def prompt_file(req: func.HttpRequest, result: str) -> func.HttpResponse:
    result_json = json.loads(result)
    response_json = {
        "content": result_json.get("Response"),
        "content_type": "text/plain"
    }
    return func.HttpResponse(json.dumps(response_json), status_code=200, mimetype="application/json")