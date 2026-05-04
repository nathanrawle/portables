---
name: standard-development-loop
description: Use only when the user explicitly asks for the standard development loop or explicitly asks for a multi-agent coding workflow. Do not use for ordinary plan-driven execution, small edits, direct questions, reviews, or when a more specific skill applies.
---

> [!NOTE]
> 1. Work **must** be completed on a topic branch, i.e. you must **not** be on the default branch (e.g. main, master), unless this instruction is explicitly overridden by the user.
> 2. The task to be completed should already be clear before invoking the steps in this skill.

Entrypoint: after this skill has been selected and the task is clear enough to plan, start here.

# Preflight
0.1) Confirm the user has explicitly authorized multi-agent work and the current runtime supports subagents; if not, stop and ask the user how to proceed.
0.2) Check the current branch. If it is a default branch such as main or master, create or switch to a topic branch unless the user explicitly overrides this requirement.
0.3) Record the base commit after the topic branch is ready. Use this recorded base commit for final architecture validation.
0.4) Read the nearest relevant repository instructions, documentation, and configuration; go to 1.1

# Planning Loops
1.1) Create a plan; go to 1.2
1.2) Pass the plan to an Architect subagent for review; go to 1.3
1.3) If the Architect suggests changes, update the plan to incorporate them: go to 1.4; else, go to 1.5
1.4) If this step has been executed once already: go to 1.5; else, go to 1.2
1.5) Reset all "Planning Loops" counts to 0; go to 1.6
1.6) Return the plan to the user for approval/feedback

Entrypoint: when the user accepts a plan or after the user resolves an issue surfaced in 2.10, start here.

# Implementation Loops
2.1) Identify the next meaningful unit of work from the plan; go to 2.2
2.2) Pass the next meaningful unit of work to a Planner subagent and ask it to create a unit-plan with the right amount of detail for implementation; go to 2.3
2.3) Pass the unit-plan to an Implementer subagent for execution; when the Implementer completes go to 2.4
2.4) Ask a Reviewer subagent to evaluate the changes the Implementer just made against the unit-plan; go to 2.5
2.5) If the Reviewer suggests changes: go to 2.7; else, go to 3.1
2.6) Pass the suggestions back to the Implementer for execution; when the Implementer completes go to 2.9
2.7) If this step has been executed twice already: go to 2.8; else, go to 2.6
2.8) Reset all "Implementation Loops" counts to 0; go to 2.10
2.9) Ask the Reviewer to evaluate the Implementer's latest changes against the latest suggestions; go to 2.5
2.10) Break the loop and ask the user how they would like to proceed.

# Update Tests
3.1) Ask a dedicated Test Implementer subagent to write new tests and/or update existing tests to cover the latest changes; go to 3.2
3.2) Select the new tests and any other appropriate tests and ask a Verifier subagent to run them; go to 3.3
3.3) Ask a dedicated Test Reviewer subagent to evaluate the changes the Test Implementer just made; go to 3.4
3.4) If the Test Reviewer suggests changes: go to 3.5; else, go to 4.1
3.5) Pass the suggestions back to the Test Implementer for execution; when the Test Implementer completes go to 3.6
3.6) If this step has been executed once already: go to 3.7; else, go to 3.8
3.7) Reset all "Update Tests" counts to 0; go to 4.1
3.8) Ask the Test Reviewer to evaluate the Test Implementer's latest changes against the latest suggestions; go to 3.4

# Update Documentation
4.1) Ask a dedicated Documentation Writer subagent to update the documentation to cover the latest changes; go to 4.2
4.2) Ask a dedicated Documentation Reviewer subagent to evaluate the changes the Documentation Writer just made; go to 4.3
4.3) If the Documentation Reviewer suggests changes: go to 4.4; else, go to 4.8
4.4) Pass the suggestions back to the Documentation Writer for execution; when the Documentation Writer completes go to 4.5
4.5) If this step has been executed once already: go to 4.6; else, go to 4.7
4.6) Reset all "Update Documentation" counts to 0; go to 4.8
4.7) Ask the Documentation Reviewer to evaluate the Documentation Writer's latest changes against the latest suggestions; go to 4.3
4.8) Stage and commit the pending changes; go to 4.9
4.9) If the plan is complete: go to 5.1; else, go to 2.1

# Architecture Validation
5.1) Ask the Architect to evaluate all changes relative to the recorded base commit against the approved plan; go to 5.2
5.2) If the Architect suggests changes: go to 5.3; else, go to 5.5
5.3) If this step has been executed once already: go to 5.4; else, go to 2.6
5.4) Reset all "Architecture Validation" counts to 0; go to 5.5
5.5) Break the loop and report back to the user.
