pnpm install --frozen-lockfile --ignore-scripts
cd scripts && ruby generate_docs_from_yaml.rb && cd ..
pnpm build
