---
name: Context-First Code Generation via Context7
description: Enforces the use of Context7 before code generation or modification.
trigger: always_on
---

# RULE: Context-First Code Generation via Context7

## Trigger
Whenever the user asks to:
1. Write new code (features, scripts, components).
2. Modify existing code.
3. Troubleshoot/Debug an error.

## Protocol
Before generating any code, you MUST execute the following "Context Check" sequence:

1. **Identify Dependencies:** Determine which specific libraries, modules, utilities, or internal APIs are relevant to the task.
2. **Execute Context7:** You MUST explicitly invoke the **Context7 MCP tool** to retrieve the necessary context.
   - *Target:* Do not attempt to read local files directly and do not rely on internal training data. You must fetch the current state of the code or documentation **from the Context7 server**.
   - *Example:* "Querying Context7 for the definition of `GraphHandler`."
3. **Verify Syntax:** Use the specific method signatures, variable names, and architectural patterns returned by the **Context7 server**.

## Mandate
You are prohibited from suggesting code fixes or writing new functions until you have confirmed you have retrieved the active context **via the Context7 interface**. If the MCP server returns no results, you must explicitly ask the user for guidance.
