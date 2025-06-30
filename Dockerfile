# mrtrix includes fsl, mrtrix, freesurfer, ants, art
FROM mrtrix3/mrtrix3:latest

# Copy uv binaries to install Python
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Add FSL and mrtrix3 to path
RUN echo 'export PATH="/opt/fsl/bin:/opt/mrtrix3/bin:$PATH"' >> /etc/profile.d/path.sh \
&& chmod +x /etc/profile.d/path.sh

# Install scilpy & tractseg dependencies
RUN apt-get update && apt-get install -y \
    git wget build-essential libblas-dev liblapack-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV SETUPTOOLS_USE_DISTUTILS=stdlib

# Download TractSeg weights
RUN mkdir -p /model/tractseg \
 && wget -O /model/tractseg/pretrained_weights_tract_segmentation_v3.npz \
      https://zenodo.org/record/3518348/files/best_weights_ep220.npz?download=1 \
 && wget -O /model/tractseg/pretrained_weights_endings_segmentation_v4.npz \
      https://zenodo.org/record/3518331/files/best_weights_ep143.npz?download=1 \
 && wget -O /model/tractseg/pretrained_weights_peak_regression_part1_v2.npz \
      https://zenodo.org/record/3239216/files/best_weights_ep62.npz?download=1 \
 && wget -O /model/tractseg/pretrained_weights_peak_regression_part2_v2.npz \
      https://zenodo.org/record/3239220/files/best_weights_ep130.npz?download=1 \
 && wget -O /model/tractseg/pretrained_weights_peak_regression_part3_v2.npz \
      https://zenodo.org/record/3239221/files/best_weights_ep91.npz?download=1 \
 && wget -O /model/tractseg/pretrained_weights_peak_regression_part4_v2.npz \
      https://zenodo.org/record/3239222/files/best_weights_ep148.npz?download=1
ENV TRACTSEG_WEIGHTS_DIR="/model/tractseg"

# Add a non-root user
RUN groupadd -r user && useradd --no-log-init -m -r -g user user
USER user
RUN ln -s /model/tractseg /home/user/.tractseg
COPY --chown=user:user --chmod=755 . /code

# Install Python dependencies using UV
RUN mkdir -p /code/.cache/matplotlib
ENV MPLCONFIGDIR=/code/.cache/matplotlib
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
ENV UV_CACHE_DIR=/code/.cache/uv
ENV UV_PYTHON_INSTALL_DIR=/code/python
WORKDIR /code

RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev \
    && uv sync --frozen --no-dev

ENTRYPOINT ["/code/scripts/entrypoint.sh"]
