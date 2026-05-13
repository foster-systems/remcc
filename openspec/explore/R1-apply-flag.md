The current process is as follows:

1. Starts locally by proposing the change branch.
2. When the change branch is pushed to the origin GitHub, opsx-apply starts to execute the change pointed out by the branch name.
3. Github Action does the job and comes back with pull request.
4. Each push to the change branch triggers opsx-apply again.

Point 4 is becoming a little bit of an issue. To finalize the whole change process until it's archived, it would be best to finalize it on the same change branch and close the merge request by merging to main the whole change, which is already archived and implemented.

Find a solution for this.
