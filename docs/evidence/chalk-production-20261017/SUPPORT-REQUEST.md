Subject: Enable gateway quota enforcement for Feel production

Team Feel, project Default, environment production (flnyc749e8d9).

Model Gateway routing works with the FEEL OpenAI connection and a key restricted to openai/gpt-6-luna and openai/gpt-6.1-sol. Creating a request-rate limit in Access → Rate limits fails with:

RateLimitService.CreateRateLimit: quota enforcement is disabled (set ROUTER_QUOTA_BACKEND)

Please enable and verify the supported quota backend for this managed environment, or provide the supported self-service procedure. We need a policy scoped to the existing FEEL app key: 30 requests per minute with a burst of 5, plus 2 concurrent requests. These are initial single-device pilot limits.

The app sends camera images. We deliberately have not added TPM or token usage budgets because the gateway documentation says those reject multimodal requests before dispatch. Please confirm the supported spending-control approach for this image workload.

No API keys or provider credentials are included in this request.
