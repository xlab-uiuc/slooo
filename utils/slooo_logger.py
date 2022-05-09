import logging

_logger = logging.getLogger(__name__)


class SloooLogger(logging.Logger):
    def __init__(self, name, level=logging.INFO, log_prefix="", *args, **kwargs):
        super().__init__(name, level)
        _handler = logging.StreamHandler()
        _handler.setLevel(level)
        self.addHandler(_handler)
        self.log_prefix = log_prefix
        self.log(
            msg=f"Initialised logger with {logging.getLevelName(self.level)}",
            level=logging.ERROR,
        )

    def log(self, msg, level=logging.INFO, *args, **kwargs):
        super().log(level, msg, *args, **kwargs)


default_logger = SloooLogger(__name__, logging.INFO)
