require "json"

module Docr::Types
  class Health
    include JSON::Serializable

    @[JSON::Field(key: "Status")]
    property status : String

    @[JSON::Field(key: "FailingStreak")]
    property failing_streak : Int64

    # Real Docker/Podman returns `null`, not `[]`, before a container's
    # first health check has actually run - found live testing
    # crystal-ansible's docker_container plugin against a freshly
    # created container with a healthcheck: any inspect() before the
    # first check crashed JSON parsing entirely (a non-nullable Array
    # against a real `null` value), not just a wrong comparison result.
    @[JSON::Field(key: "Log")]
    property log : Array(Docr::Types::HealthcheckResult)?
  end
end
