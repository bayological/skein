4. Push your branch and open a **draft** pull request. Names say what the work is and carry
   the task id:
   - **your branch** is `<type>/<slug>-<task-id>`, made for you at dispatch;
   - **the pull request title** is a conventional-commit subject with the id at the end:
     `fix(api): JSON 404 for unknown paths ({{PREFIX}}-01)`. It becomes the squashed commit on
     `{{BASE}}`, and the plan reads it to know the task merged.

   Never push to `{{BASE}}`, never merge, never force-push a branch that is not yours.
