---
trigger: always_on
---

# RULE: Token-Efficient Memory Management via MCP

## Context
The user requires strict minimization of LLM token usage. Do not rely on the default chat history or Antigravity's built-in "Knowledge Items" for retrieving project context, preferences, or architectural decisions.

## Protocol
You must utilize the memory MCP tool for all project knowledge and preference retrieval. Do not use this for reading raw source code.

### 1. Retrieval (Start of Task)
Before writing code or answering complex queries, you MUST query the Knowledge Graph:
- **Action:** Use `memory.search_nodes` or `memory.open_nodes`.
- **Target:** Search for relevant entities (e.g., "UserPreferences", "ProjectArchitecture", "ActiveFeatureSpec").
- **Constraint:** Do not ask the user for information that should already be in the Knowledge Graph.

### 2. Storage (End of Task)
After successfully completing a task or learning a new fact, you MUST update the Knowledge Graph:
- **Action:** Use `memory.create_entities` or `memory.create_relations`.
- **Content:** Store architectural decisions, user preferences, or specific library versions used.
- **Format:** Ensure observations are atomic strings (e.g., "Project uses React v18", "User prefers arrow functions").

## Mandate
- **Minimize Context:** Do not "scroll up" in the chat history to find old code snippets. Query the memory server instead.
- **Fail Gracefully:** If the memory server returns no results, explicitly ask the user for the info and then *immediately* store their answer into memory for next time.