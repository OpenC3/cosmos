export RUBYGEMS_URL=https://rubygems.org
openc3_path=$(dirname $(dirname $(pwd)))
openc3_path+="/openc3"
export OPENC3_DEVEL=$openc3_path
echo "OPENC3_DEVEL set to $OPENC3_DEVEL"

bundle config set --local with :DEVELOPMENT

cd ../..
bundle install
cd openc3
bundle install
bundle exec rake build
cd ../openc3-cosmos-cmd-tlm-api
bundle install
bundle exec rspec
