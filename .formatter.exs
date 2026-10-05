[
  import_deps: [:jido, :jido_action, :jido_ai],
  locals_without_parens: [imp: 2],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
