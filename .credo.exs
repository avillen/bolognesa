%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: [
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
