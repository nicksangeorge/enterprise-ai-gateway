
## QUICKSTART.md — Fixes Found During Validation

- [ ] `terraform plan -out=deploy.tfplan` — the `=` sign fails on Windows PowerShell. Use space: `terraform plan -out deploy.tfplan`. Fix in QUICKSTART Step 1.
- [ ] Teardown section — simplify to `az group delete` instead of requiring manual cleanup before `terraform destroy`
- [ ] Add a plain-english 1-liner sub-heading under each step explaining what it does and why (e.g., Step 7: "Register the MCP server so APIM can proxy and govern tool calls"). Helps users understand the flow without reading all the details.
- [ ] Step 6 "See results" — some of the KQL queries are breaking. Needs investigation and fix. Check the chargeback metrics query in App Insights specifically.
