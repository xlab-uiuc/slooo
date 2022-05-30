import sys
import time
import logging
from turtle import up

class LogsManager:
    def __init__(self):
        pass

    def add_default_handler(self, out_stream=sys.stdout):
        handler = logging.StreamHandler(stream=out_stream)
        formatter = logging.Formatter('{"time":"%(asctime)s", "name": "%(name)s", "level": "%(levelname)s", "message": "%(message)s"}')
        logging.root.handlers = []
        handler.setFormatter(formatter)
        logging.root.addHandler(handler)
        logging.root.setLevel(logging.INFO)

    def setup(self):
        self.add_default_handler()


def setup_logs():
    logsManager = LogsManager()
    logsManager.setup()

def get_log_level():
    return logging.getLevelName(logging.root.getEffectiveLevel())

def update_log_level(level):
    loggers = [logging.getLogger(name) for name in logging.root.manager.loggerDict]

    def _update(new_level):
        logging.root.setLevel(new_level)
        for logger in loggers:
            logger.setLevel(new_level)

    prev_level = get_log_level()
    if level.lower() == "info":
        _update(logging.INFO)
    elif level.lower() == "error":
        _update(logging.ERROR)
    elif level.lower() == "debug":
        _update(logging.DEBUG)
    elif level.lower() == "warn":
        _update(logging.WARN)
    curr_level = get_log_level()
    logging.critical(
        f"Updated Logger level from {prev_level} to {curr_level}"
    )
    return curr_level