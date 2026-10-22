4. This repo has no remote (skein local mode): leave the work committed on your branch. Do not
   push and do not open a pull request. Names say what the work is and carry the task id:
   - **your branch** is `<type>/<slug>-<task-id>`, made for you at dispatch;
   - `skein merge` squashes the branch onto `{{BASE}}` as one commit,
     `<type>: <summary> (<task-id>)`, and the plan reads that subject to know the task merged.

   Never commit to `{{BASE}}`, never merge, never rewrite a branch that is not yours.
