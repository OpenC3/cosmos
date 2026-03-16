# Remove warnings in CGI
saved_verbose = $VERBOSE
$VERBOSE = false
require 'faraday'
$VERBOSE = saved_verbose

module Faraday
  class Response
    # Add an alias of status to code to feel more like httpclient
    alias code status
  end
end