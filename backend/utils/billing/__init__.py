"""Provider-neutral billing boundary.

Import concrete types from their owning modules so the model/config dependency
graph stays acyclic. Only ``provider.py`` imports the provider SDK.
"""
