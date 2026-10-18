"""
Schemathesis hooks for testing the admin operations with credentials.

Schemathesis doesn't always use the values that schemathesis.toml binds
to a parameter, e.g. not for the examples in api.yaml. Before each request
that can change data, this hook therefore points it at the throwaway corpus
`scratch`, so that the test data the other tests rely on is never changed.
The corpus is created before the run (see test/schemathesis.sh) and kept
until the end: deleting a whole corpus is left to the tests in test/admin.
"""

import schemathesis

SCRATCH_CORPUS = "scratch"
# a corpus that never exists, for DELETE /corpora/{corpusname}
MISSING_CORPUS = "nosuchcorpus"


@schemathesis.hook
def before_call(ctx, case, **kwargs):
    if case.method.upper() == "GET":
        return
    if "corpusname" in (case.path_parameters or {}):
        if case.operation.path == "/corpora/{corpusname}" and case.method.upper() == "DELETE":
            case.path_parameters["corpusname"] = MISSING_CORPUS
        else:
            case.path_parameters["corpusname"] = SCRATCH_CORPUS
    # the JSON body of POST /corpora names the corpus to create
    if isinstance(case.body, dict) and "name" in case.body:
        case.body["name"] = SCRATCH_CORPUS
