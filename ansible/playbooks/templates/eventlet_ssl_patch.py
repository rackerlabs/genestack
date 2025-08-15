import os, ssl

os.environ.setdefault("EVENTLET_NO_GREENDNS", "yes")
try:
    from eventlet.green import ssl as gssl

    def _safe_green_create_default_context(*a, **kw):
        return ssl._create_default_https_context(*a, **kw)

    gssl.green_create_default_context = _safe_green_create_default_context
except Exception as e:
    # don't crash the process if eventlet isn't here yet
    pass
