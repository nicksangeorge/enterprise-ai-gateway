# Deep dives

This demo covers the integrated enterprise story. For hands-on exploration of individual capabilities, use these labs from the [Azure-Samples/AI-Gateway](https://github.com/Azure-Samples/ai-gateway) repository. Each is a self-contained Jupyter notebook with Bicep templates and APIM policies.

## Models

| Capability | Lab | What it covers |
|-----------|-----|---------------|
| Load balancing | [Backend Pool Load Balancing](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/backend-pool-load-balancing/backend-pool-load-balancing.ipynb) | Distribute requests across multiple model endpoints with priority and weighted routing |
| Token rate limiting | [Token Rate Limiting](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/token-rate-limiting/token-rate-limiting.ipynb) | Control token consumption with TPM limits per consumer |
| Semantic caching | [Semantic Caching](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/semantic-caching/semantic-caching.ipynb) | Cache completions using vector similarity via Azure Managed Redis |
| Model routing | [Model Routing](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/model-routing/model-routing.ipynb) | Route to different backends based on model and version |
| Cost management | [FinOps Framework](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/finops-framework/finops-framework.ipynb) | Budget controls and automated quota management |

## Tools (MCP)

| Capability | Lab | What it covers |
|-----------|-----|---------------|
| MCP protocol | [Model Context Protocol](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/model-context-protocol/model-context-protocol.ipynb) | MCP servers with OAuth credential management through APIM |
| MCP client auth | [MCP Client Authorization](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/mcp-client-authorization/mcp-client-authorization.ipynb) | Implement MCP with the client authorization flow |
| Function calling | [Function Calling](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/function-calling/function-calling.ipynb) | OpenAI function calling with Azure Functions backend |

## Agents

| Capability | Lab | What it covers |
|-----------|-----|---------------|
| Agent service | [AI Agent Service](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/ai-agent-service/ai-agent-service-v2.ipynb) | Foundry Agent Service with multi-service control |
| A2A agents | [A2A Enabled Agents](https://github.com/Azure-Samples/AI-Gateway/blob/main/labs/mcp-a2a-agents/mcp-agent-as-a2a-server.ipynb) | Agent-to-agent protocol with MCP tools |

## Additional resources

- [AI Gateway Workshop](https://aka.ms/ai-gateway/workshop): structured walkthrough of core capabilities
- [Enterprise AI Gateway eBook](https://github.com/Azure-Samples/AI-Gateway/blob/main/docs/media/Enterprise%20AI%20Gateway%20eBook%20-%20Feb%202026.pdf): end-to-end architecture guide
- [AI Gateway reference architecture](https://learn.microsoft.com/en-us/ai/playbook/technology-guidance/generative-ai/dev-starters/genai-gateway/reference-architectures/apim-based): Microsoft's official reference
- [Secure remote MCP via APIM sample](https://github.com/Azure-Samples/remote-mcp-apim-functions-python): Python/Functions/OAuth implementation
