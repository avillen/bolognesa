# Library false positives under OTP 28's stricter opaque checks; the flagged code is not ours.
[
  # Ecto.Multi.new/0 builds a MapSet literal that Dialyzer reads as breaking MapSet's opacity.
  {"lib/bolognesa/libraries/infrastructure/repositories/ecto_scan_repository.ex",
   :call_without_opaque},
  # Generated Phoenix show/hide default to a %JS{} literal, violating JS's opaque ops type.
  {"lib/bolognesa_web/components/core_components.ex", :contract_with_opaque},
  # Gettext's compiled plural forms pass an Expo struct that breaks its opaque plural type.
  {"lib/bolognesa_web/gettext.ex", :call_without_opaque}
]
