require "./spec_helper"

describe Docr::Types::LogConfig do
  it "parses a Config: null (e.g. Podman's journald driver returns this)" do
    json = %({"Type": "journald", "Config": null})
    log_config = Docr::Types::LogConfig.from_json(json)

    log_config.type.should eq "journald"
    log_config.config.should be_nil
  end

  it "parses a populated Config object" do
    json = %({"Type": "json-file", "Config": {"max-size": "10m"}})
    log_config = Docr::Types::LogConfig.from_json(json)

    log_config.type.should eq "json-file"
    log_config.config.should eq({"max-size" => "10m"})
  end
end
