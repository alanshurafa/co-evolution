FROM python:3.11-slim@sha256:9534e5a8e315485d4061ed659af0fd78a284c015f9b73661b41d6bab25604534
RUN pip install --no-cache-dir numpy==1.26.4 sympy==1.14.0 tqdm==4.67.1
COPY livecodebench-upstream/lcb_runner /lcb/lcb_runner
COPY reasoning-gym-upstream/reasoning_gym /rg/reasoning_gym
COPY verifier.py /verifier.py
ENV PYTHONDONTWRITEBYTECODE=1
WORKDIR /tmp
ENTRYPOINT ["python", "/verifier.py"]
