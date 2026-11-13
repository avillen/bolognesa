%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
          {Credo.Check.Design.AliasUsage,
           excluded_namespaces: [], excluded_lastnames: [], if_referenced: false},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Readability.StrictModuleLayout,
           order: [:type, :defstruct],
           ignore: [
             :shortdoc,
             :moduledoc,
             :behaviour,
             :use,
             :import,
             :alias,
             :require,
             :module_attribute,
             :typep,
             :opaque,
             :callback,
             :macrocallback,
             :optional_callbacks,
             :module
           ]}
        ]
      }
    }
  ]
}
