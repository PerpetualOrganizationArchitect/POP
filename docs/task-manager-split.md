# TaskManager Library Split Architecture

## Current State
`src/TaskManager.sol` (~1100 lines) covers:
- Projects
- Tasks
- Applications
- Permissions
- Budgets
- Folders
- Lens dispatcher

## Proposed Structure

```
src/
  task-manager/
    TaskManager.sol          (main contract, delegates to libraries)
    libraries/
      TaskProjects.sol       (project CRUD, caps)
      TaskActions.sol        (task lifecycle, assignments)
      TaskApplications.sol   (application handling)
      TaskPermissions.sol    (permission bits, role checks)
      TaskBudgets.sol        (budget resizing, PT caps)
      TaskFolders.sol        (folder operations)
      TaskLens.sol           (view/dispatcher functions)
```

## Migration Steps

1. Extract each concern into a standalone library
2. Use `using ... for` pattern (same as HybridVoting)
3. TaskManager becomes thin dispatcher
4. Maintain shared storage layout
5. Add NatSpec to all extracted functions

## Benefits
- Better code organization
- Easier auditing per concern
- Parallel development
- Reduced merge conflicts
