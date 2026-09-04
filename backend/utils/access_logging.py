"""Sanitize server access logs before they reach hosted logging sinks."""

import logging


class _UvicornAccessTargetSanitizer(logging.Filter):
    """Remove query strings from Uvicorn's structured access-log arguments."""

    def filter(self, record: logging.LogRecord) -> bool:
        arguments = record.args
        if not isinstance(arguments, tuple) or len(arguments) < 3 or not isinstance(arguments[2], str):
            return True

        request_target = arguments[2]
        path, separator, _query = request_target.partition('?')
        if not separator:
            return True

        sanitized_arguments = list(arguments)
        sanitized_arguments[2] = path
        record.args = tuple(sanitized_arguments)
        return True


def install_uvicorn_access_log_sanitizer(logger: logging.Logger | None = None) -> None:
    """Install the process-wide query-string sanitizer once."""

    access_logger = logger or logging.getLogger('uvicorn.access')
    if any(isinstance(existing, _UvicornAccessTargetSanitizer) for existing in access_logger.filters):
        return
    access_logger.addFilter(_UvicornAccessTargetSanitizer())
