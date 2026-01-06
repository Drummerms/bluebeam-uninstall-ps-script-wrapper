---
description: Autonomous recursive loop for completing complex tasks
---

# Ralph Loop Workflow (Auto-Run Mode)

**Step 1: State Check**
Read the `RALPH_MEMORY.md` file.
- If it does not exist, CREATE it with a step-by-step plan based on the user's last request.
- If it exists, identify the next unchecked `[ ]` task.

**Step 2: Execution**
Execute the next task found in Step 1.
- ⚠️ **CRITICAL:** You must strictly adhere to **Workspace Rule 2** (Context7) before writing any code.
- ⚠️ **CRITICAL:** Consult **Workspace Rule 1** (Memory MCP) if you need architectural context or user preferences to complete the task.
- **Verification:** After editing, you MUST run a test or verification command.

**Step 3: State Update**
- If the task was successful, mark it `[x]` in `RALPH_MEMORY.md`.
- If failed, add a sub-task to fix the error.

**Step 4: Internal Recursion**
- Check if there are remaining `[ ]` items in `RALPH_MEMORY.md`.
- **IF UNFINISHED:** Do not stop. Immediately return to **Step 1** and process the next item within this same response. Continue this loop until all tasks are complete or you encounter a blocking error.
- **IF FINISHED:** Print "Mission Complete" and stop.