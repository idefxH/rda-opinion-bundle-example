# v0: multi-stage build on SUSE BCI. When SUSE-AppCo buildpacks ship,
# this Dockerfile becomes optional — `pack build --builder
# registry.suse.com/rda/builder:latest` produces an equivalent image
# without a Dockerfile.

FROM registry.suse.com/bci/nodejs:22 AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

FROM registry.suse.com/bci/nodejs:22
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
EXPOSE 8080
USER 1000:1000
CMD ["node", "/app/src/index.js"]
