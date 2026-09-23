# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# base: shared Python runtime (Debian bookworm, Python 3.8)
# ---------------------------------------------------------------------------
FROM python:3.8-slim-bookworm AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ---------------------------------------------------------------------------
# deps: install pinned requirements into an isolated virtualenv.
# Every pinned package ships a manylinux wheel for CPython 3.8 (or is pure
# Python), so no compiler toolchain is needed.
# ---------------------------------------------------------------------------
FROM base AS deps

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# ---------------------------------------------------------------------------
# runner: minimal runtime image, runs as an unprivileged user (uid/gid 1001).
#
# No JRE is installed: tabula-py (Java) is only used by the crawler when the
# DNIT "personas juridicas" archive contains a PDF. The archive currently
# ships an .xls file, which is parsed by pandas/xlrd. If DNIT switches back
# to PDF, add `default-jre-headless` here.
# ---------------------------------------------------------------------------
FROM base AS runner

RUN groupadd --system --gid 1001 app \
    && useradd --system --uid 1001 --gid 1001 --home-dir /code --no-create-home app

COPY --from=deps /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /code

COPY entrypoint.sh /code/entrypoint.sh
# Strip CRLF in case the repository was checked out on Windows.
RUN sed -i 's/\r$//' /code/entrypoint.sh && chmod 0755 /code/entrypoint.sh

COPY manage.py wsgi-service.py /code/
COPY app /code/app

# The data directory is created here (owned by 1001) so that a fresh named
# volume mounted on /code/data inherits this ownership.
RUN mkdir -p /code/data/tmp && chown -R 1001:1001 /code/data

USER 1001:1001

EXPOSE 3000

ENTRYPOINT ["/code/entrypoint.sh"]
CMD ["runserver"]
