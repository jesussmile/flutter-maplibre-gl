---
description: Project-specific rules for Flutter MapLibre GL development with task management.
globs: **/*
alwaysApply: true
---

# Flutter MapLibre GL Project Rules - Taskmaster

## 🎯 Primary Directive

**ALWAYS follow and update the task management system located at:**
`/Users/pannam/Desktop/flight_canvas/flutter-maplibre-gl/.kiro/specs/native-triangle-layer/tasks.md`

## 📋 Task Management Instructions

### For AI Assistant:
1. **Check tasks.md first** - Always reference the current task status before starting work
2. **Update task status** - Change task status as work progresses:
   - ⏳ [NOT STARTED] → 🔄 [IN PROGRESS] when starting
   - 🔄 [IN PROGRESS] → ✅ [COMPLETED] when finished
   - 🔄 [IN PROGRESS] → ❌ [BLOCKED] if dependencies block progress
   - ✅ [COMPLETED] → ⚠️ [NEEDS REVIEW] if review required

3. **Update progress dashboard** - Keep the status dashboard current:
   - Update overall progress percentage
   - Update phase progress counters
   - Update current phase indicator
   - Update overall status color (🔴/🟡/🟢)

4. **Follow task sequence** - Complete tasks in order within each phase
5. **Document blockers** - If a task becomes blocked, note the reason

### For Human Developer:
- Reference tasks.md for current project status
- Update task status when completing work
- Add notes or comments to tasks as needed

## 🚫 Implementation Constraints

**CRITICAL - These constraints apply to ALL triangle layer work:**

1. **Platform Scope**: Android and iOS ONLY
2. **Rendering Method**: Native GPU shaders ONLY
3. **Forbidden Approaches**: 
   - NO PNG generation
   - NO sprite images
   - NO SDF images
   - NO symbol-based fallbacks
   - NO image-based rendering of any kind

4. **Architecture**: Must mirror circle layer implementation exactly

## 📊 Progress Tracking

**Current Status**: See tasks.md dashboard  
**Next Action**: Check tasks.md for current phase and next task  
**Blockers**: See tasks.md for any blocked tasks  

---

**Remember**: This document points to tasks.md as the single source of truth for project progress and task management.