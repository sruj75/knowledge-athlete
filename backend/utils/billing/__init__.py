"""Provider-neutral billing boundary.

Import concrete types from their owning modules so the model/config dependency
graph stays acyclic. ``factory.py`` is the sole lazy module-loader boundary;
``provider.py`` statically imports the provider SDK for active operations.
"""
