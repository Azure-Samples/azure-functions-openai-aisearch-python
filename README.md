<!--
---
name: Azure Function using OpenAI trigger and bindings extension to highlight OpenAI retrieval augmented generation with Azure AI Search.
description: This repository contains an Azure Function using OpenAI trigger and bindings extension to highlight OpenAI retrieval augmented generation with Azure AI Search. The sample uses managed identity.
page_type: sample
products:
- azure-functions
- azure
- entra-id
urlFragment: azure-functions-openai-aisearch-dotnet8
languages:
- csharp
- bicep
- azdeveloper
---
-->

# Azure Functions
## Using Azure Functions OpenAI trigger and bindings extension to import data and query with Azure Open AI and Azure AI Search

This sample contains an Azure Function using OpenAI bindings extension to highlight OpenAI retrieval augmented generation with Azure AI Search.

You can learn more about the OpenAI trigger and bindings extension in the [GitHub documentation](https://github.com/Azure/azure-functions-openai-extension) and in the [Official OpenAI extension documentation](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-openai)


## Prerequisites

* [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/6.0) or greater (Visual Studio 2022 recommended)
* [Azure Functions Core Tools v4.x](https://learn.microsoft.com/azure/azure-functions/functions-run-local?tabs=v4%2Cwindows%2Cnode%2Cportal%2Cbash)
* [Azure OpenAI resource](https://learn.microsoft.com/azure/openai/overview)
* [Azure AI Search resource](https://learn.microsoft.com/en-us/azure/search/)
* [Azurite](https://github.com/Azure/Azurite)
* [Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd) to create Azure resources automatically - recommended

## Prepare your local environment

### Create Azure OpenAI and Azure AI Search resources for local and cloud dev-test

Once you have your Azure subscription, run the following in a new terminal window to create Azure OpenAI, Azure AI Search and other resources needed: You will be asked if you want to enable a virtual network that will lock down your OpenAI and AI Search services so they are only available from the deployed function app over private endpoints. To skip virtual network integration, select true. If you select networking, your local IP will be added to the OpenAI and AI Search services so you can debug locally.
```bash
azd init --template https://github.com/Azure-Samples/azure-functions-openai-aisearch-dotnet
```
Mac/Linux:
```bash
chmod +x ./infra/scripts/*.sh 
```
Windows:
```Powershell
set-executionpolicy remotesigned
```
Run the follow command to provision resoruces in Azure
```bash
azd provision
```

If you don't run azd provision, you can create an [OpenAI resource](https://portal.azure.com/#create/Microsoft.CognitiveServicesOpenAI) and an [AI Search resource](https://portal.azure.com/#create/Microsoft.Search) in the Azure portal to get your endpoints. After it deploys, click Go to resource and view the Endpoint value.  You will also need to deploy a model, e.g. with name `chat` with model `gpt-35-turbo` and `embeddings` with model `text-embedding-3-small`

### Create local.settings.json (Should be in the same folder as host.json. Automatically created if you ran azd provision)
```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "dotnet-isolated",
    "AZURE_OPENAI_ENDPOINT": "<paste from above>",
    "CHAT_MODEL_DEPLOYMENT_NAME": "chat",
    "AZURE_AISEARCH_ENDPOINT": "<paste from above>",
    "EMBEDDING_MODEL_DEPLOYMENT_NAME": "embeddings",
    "SYSTEM_PROMPT": "You must only use the provided documents to answer the question"
    }
}
```

### Permissions
#### Add your account (contoso.microsoft.com) with the following permissions to the Azure OpenAI and AI Search resources when testing locally.
If you used `azd provision` this step is already done - your logged in user and your function's managed idenitty already have permissions granted. 
* Cognitive Services OpenAI User (OpenAI resource)
* Azure Search Service Contributor (AI Search resource)
* Azure Search Index Data Contributor (AI Search resource)
 

### Access to Azure OpenAI and Azure AI Search with virtual network integration
If you selected virtual network integration, access to Azure OpenAI and Azure AI Search is limited to the Azure Function app through private endpoints and cannot be reached from the internet. To allow testing from your local machine, you need to go to the networking tab in Azure OpenAI and Azure AI Search and add your client ip to the allowed list. If you used `azd provision` this step is already done.

## Run your app using Visual Studio Code

1. Open the folder in a new terminal.
1. Run the `code .` code command to open the project in Visual Studio Code.
1. In the command palette (F1), type `Azurite: Start`, which enables debugging without warnings.
1. Press **Run/Debug (F5)** to run in the debugger. Select **Debug anyway** if prompted about local emulator not running.
1. Send POST requests to the `ingest` and `ask` endpoints respectively using your HTTP test tool. If you have the [RestClient](https://marketplace.visualstudio.com/items?itemName=humao.rest-client) extension installed, you can execute requests directly from the [`test.http`](./app/test.http) project file.

## Run your app using Visual Studio

1. Open the `AISearchSample.sln` solution file in Visual Studio.
1. Press **Run/F5** to run in the debugger. Make a note of the `localhost` URL endpoints, including the port, which might not be `7071`.
1. Open the [`test.http`](./app/test.http) project file, update the port on the `localhost` URL (if needed), and then use the built-in HTTP client to call the `ingest` and `ask` endpoints.


## Deploy to Azure

Run this command to provision the function app, with any required Azure resources, and deploy your code:

```shell
azd up
```

You're prompted to supply these required deployment parameters:

| Parameter | Description |
| ---- | ---- |
| _Environment name_ | An environment that's used to maintain a unique deployment context for your app. You won't be prompted if you created the local project using `azd init`.|
| _Azure subscription_ | Subscription in which your resources are created.|
| _Azure location_ | Azure region in which to create the resource group that contains the new Azure resources. Only regions that currently support the Flex Consumption plan are shown.|

After publish completes successfully, `azd` provides you with the URL endpoints of your new functions, but without the function key values required to access the endpoints. To learn how to obtain these same endpoints along with the required function keys, see [Invoke the function on Azure](https://learn.microsoft.com/azure/azure-functions/create-first-function-azure-developer-cli?pivots=programming-language-dotnet#invoke-the-function-on-azure) in the companion article [Quickstart: Create and deploy functions to Azure Functions using the Azure Developer CLI](https://learn.microsoft.com/azure/azure-functions/create-first-function-azure-developer-cli?pivots=programming-language-dotnet).

## Redeploy your code

You can run the `azd up` command as many times as you need to both provision your Azure resources and deploy code updates to your function app.

>[!NOTE]
>Deployed code files are always overwritten by the latest deployment package.

## Clean up resources

When you're done working with your function app and related resources, you can use this command to delete the function app and its related resources from Azure and avoid incurring any further costs (--purge does not leave a soft delete of AI resource and recovers your quota):

```shell
azd down --purge
```
