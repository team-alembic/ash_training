defmodule Twitter.Archival.Info do
  @moduledoc "Introspection helpers for `Twitter.Archival`, e.g. `archive_attribute!/1`."
  use Spark.InfoGenerator, extension: Twitter.Archival, sections: [:archive]
end
