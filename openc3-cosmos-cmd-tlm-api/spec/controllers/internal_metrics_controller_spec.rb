# encoding: ascii-8bit

# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.

require "rails_helper"

RSpec.describe InternalMetricsController, type: :controller do
  before(:each) do
    mock_redis
    allow(OpenC3::Logger).to receive(:debug)
    allow(OpenC3::Logger).to receive(:error)
  end

  describe "GET index" do
    context "when successful" do
      before(:each) do
        allow(OpenC3::ScopeModel).to receive(:names).and_return(["DEFAULT", "TEST"])
      end

      it "returns metrics in Prometheus format for single metric" do
        metrics_data = {
          "metric1" => {
            "metric_name" => "http_requests_total",
            "label_list" => [
              {
                "method" => "GET",
                "path" => "/api",
                "metric__value" => 42.0
              }
            ]
          }
        }

        allow(OpenC3::MetricModel).to receive(:all).with(scope: "DEFAULT").and_return(metrics_data)
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "TEST").and_return({})

        get :index

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("text/plain; charset=utf-8")

        body = response.body
        expect(body).to include("# TYPE http_requests_total histogram")
        expect(body).to include("# HELP http_requests_total internal metric generated from openc3/utilities/metric.rb.")
        expect(body).to include('http_requests_total{method="GET",path="/api"} 42.0')
      end

      it "returns metrics for multiple scopes and metrics" do
        default_metrics = {
          "metric1" => {
            "metric_name" => "http_requests_total",
            "label_list" => [
              {
                "method" => "GET",
                "path" => "/api",
                "metric__value" => 10.0
              },
              {
                "method" => "POST",
                "path" => "/api",
                "metric__value" => 5.0
              }
            ]
          }
        }

        test_metrics = {
          "metric2" => {
            "metric_name" => "database_queries_total",
            "label_list" => [
              {
                "table" => "users",
                "operation" => "select",
                "metric__value" => 100.0
              }
            ]
          }
        }

        allow(OpenC3::MetricModel).to receive(:all).with(scope: "DEFAULT").and_return(default_metrics)
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "TEST").and_return(test_metrics)

        get :index

        expect(response).to have_http_status(:ok)

        body = response.body

        expect(body).to include("# TYPE http_requests_total histogram")
        expect(body).to include('http_requests_total{method="GET",path="/api"} 10.0')
        expect(body).to include('http_requests_total{method="POST",path="/api"} 5.0')

        expect(body).to include("# TYPE database_queries_total histogram")
        expect(body).to include('database_queries_total{table="users",operation="select"} 100.0')
      end

      it "handles metrics with same name from different scopes" do
        default_metrics = {
          "metric1" => {
            "metric_name" => "requests_total",
            "label_list" => [
              {
                "service" => "api",
                "metric__value" => 50.0
              }
            ]
          }
        }

        test_metrics = {
          "metric2" => {
            "metric_name" => "requests_total",
            "label_list" => [
              {
                "service" => "web",
                "metric__value" => 30.0
              }
            ]
          }
        }

        allow(OpenC3::MetricModel).to receive(:all).with(scope: "DEFAULT").and_return(default_metrics)
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "TEST").and_return(test_metrics)

        get :index

        expect(response).to have_http_status(:ok)

        body = response.body
        # Should only have one TYPE and HELP section for requests_total
        expect(body.scan("# TYPE requests_total histogram").length).to eq(1)
        expect(body.scan("# HELP requests_total").length).to eq(1)

        # Should have both metrics with different labels
        expect(body).to include('requests_total{service="api"} 50.0')
        expect(body).to include('requests_total{service="web"} 30.0')
      end

      it "handles empty metrics gracefully" do
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "DEFAULT").and_return({})
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "TEST").and_return({})

        get :index

        expect(response).to have_http_status(:ok)
        expect(response.body).to be_empty
      end

      it "handles metrics with multiple labels correctly" do
        metrics_data = {
          "metric1" => {
            "metric_name" => "complex_metric",
            "label_list" => [
              {
                "method" => "GET",
                "status" => "200",
                "endpoint" => "/health",
                "instance" => "server1",
                "metric__value" => 123.45
              }
            ]
          }
        }

        allow(OpenC3::MetricModel).to receive(:all).with(scope: "DEFAULT").and_return(metrics_data)
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "TEST").and_return({})

        get :index

        expect(response).to have_http_status(:ok)

        body = response.body
        expect(body).to include("# TYPE complex_metric histogram")
        # Check that all labels are present in the output (order may vary)
        metric_line = body.lines.find { |line| line.start_with?("complex_metric{") }
        expect(metric_line).to include('method="GET"')
        expect(metric_line).to include('status="200"')
        expect(metric_line).to include('endpoint="/health"')
        expect(metric_line).to include('instance="server1"')
        expect(metric_line).to include("123.45")
      end

      it "handles metrics with no labels" do
        metrics_data = {
          "metric1" => {
            "metric_name" => "simple_counter",
            "label_list" => [
              {
                "metric__value" => 999.0
              }
            ]
          }
        }

        allow(OpenC3::MetricModel).to receive(:all).with(scope: "DEFAULT").and_return(metrics_data)
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "TEST").and_return({})

        get :index

        expect(response).to have_http_status(:ok)

        body = response.body
        expect(body).to include("# TYPE simple_counter histogram")
        expect(body).to include("simple_counter{} 999.0")
      end
    end

    context "when ScopeModel.names fails" do
      it "returns 500 error when cannot access scopes" do
        allow(OpenC3::ScopeModel).to receive(:names).and_raise(RuntimeError.new("Redis connection failed"))

        get :index

        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to eq("failed to access datastore")
        expect(OpenC3::Logger).to have_received(:error).with("failed to connect to redis to pull scopes")
      end
    end

    context "when MetricModel.all fails" do
      it "returns 500 error when cannot access metrics" do
        allow(OpenC3::ScopeModel).to receive(:names).and_return(["DEFAULT"])
        allow(OpenC3::MetricModel).to receive(:all).and_raise(RuntimeError.new("Redis connection failed"))

        get :index

        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to eq("failed to access datastore")
        expect(OpenC3::Logger).to have_received(:error).with("failed to connect to redis to pull metrics")
      end
    end

    context "logging behavior" do
      before(:each) do
        allow(OpenC3::ScopeModel).to receive(:names).and_return(["DEFAULT"])
        allow(OpenC3::MetricModel).to receive(:all).and_return({})
      end

      it "logs debug information about the request" do
        get :index

        expect(OpenC3::Logger).to have_received(:debug).with("request for aggregator metrics")
        expect(OpenC3::Logger).to have_received(:debug).with("ScopeModels: [\"DEFAULT\"]")
        expect(OpenC3::Logger).to have_received(:debug).with("search metrics for scope: DEFAULT")
        expect(OpenC3::Logger).to have_received(:debug).with("metrics search for scope: DEFAULT, returned: {}")
      end
    end

    context "edge cases" do
      it "handles special characters in label values" do
        metrics_data = {
          "metric1" => {
            "metric_name" => "special_chars_metric",
            "label_list" => [
              {
                "path" => "/api/special\"chars\\here",
                "message" => "Hello, World!",
                "metric__value" => 1.0
              }
            ]
          }
        }

        allow(OpenC3::ScopeModel).to receive(:names).and_return(["DEFAULT"])
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "DEFAULT").and_return(metrics_data)

        get :index

        expect(response).to have_http_status(:ok)

        body = response.body
        expect(body).to include('path="/api/special"chars\\here"')
        expect(body).to include('message="Hello, World!"')
      end

      it "handles numeric and boolean label values" do
        metrics_data = {
          "metric1" => {
            "metric_name" => "mixed_types_metric",
            "label_list" => [
              {
                "numeric_label" => 123,
                "boolean_label" => true,
                "string_label" => "text",
                "metric__value" => 5.5
              }
            ]
          }
        }

        allow(OpenC3::ScopeModel).to receive(:names).and_return(["DEFAULT"])
        allow(OpenC3::MetricModel).to receive(:all).with(scope: "DEFAULT").and_return(metrics_data)

        get :index

        expect(response).to have_http_status(:ok)

        body = response.body
        expect(body).to include('numeric_label="123"')
        expect(body).to include('boolean_label="true"')
        expect(body).to include('string_label="text"')
      end
    end
  end
end
