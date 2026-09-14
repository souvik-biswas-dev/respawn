# Build and push (done by CI in step 9; by hand until then):
#   docker build -t ghcr.io/<your-user>/respawn-canary:0.1.0 gitops/apps/canary/writer
#   docker push ghcr.io/<your-user>/respawn-canary:0.1.0
# Then set the same name in gitops/apps/canary/kustomization.yaml under `images:`.
FROM python:3.12-slim

RUN pip install --no-cache-dir "psycopg[binary]==3.2.3" \
 && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin canary

WORKDIR /app
COPY app.py .
USER 10001
EXPOSE 8080
CMD ["python", "-u", "app.py"]
