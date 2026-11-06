# The sample seed is intentionally restricted to an empty, dedicated demo database.
alias Bolognesa.Repo
alias Bolognesa.Infrastructure.Persistence.{LibrarySchema, UserSchema}

if not String.starts_with?(System.fetch_env!("BOLOGNESA_DB_NAME"), "bolognesa_demo_") do
  raise "Demo data requires a dedicated demo database"
end

root = System.fetch_env!("BOLOGNESA_LIBRARY_ROOTS")

if Repo.exists?(UserSchema) or Repo.exists?(LibrarySchema) do
  if File.exists?(Path.join(root, "sample-ids.json")) do
    IO.puts("Demo data already exists; leaving it unchanged.")
    System.halt(0)
  end

  Mix.raise("Demo database already contains data. It has been left unchanged.")
end

File.mkdir_p!(root)
video = Path.join(root, "sample.webm")

{output, status} =
  System.cmd(
    "ffmpeg",
    [
      "-y",
      "-loglevel",
      "error",
      "-f",
      "lavfi",
      "-i",
      "testsrc=size=640x360:rate=24",
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=440:sample_rate=44100",
      "-t",
      "10",
      "-c:v",
      "libvpx",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "libvorbis",
      video
    ], stderr_to_stdout: true)

if status != 0, do: Mix.raise("Could not generate sample video: #{output}")
System.put_env("BOLOGNESA_LOCAL_DEMO", "1")
System.put_env("BOLOGNESA_SCREENSHOT_VIDEO", video)
System.put_env("BOLOGNESA_SCREENSHOT_IDS", Path.join(root, "sample-ids.json"))
Code.require_file("../screenshots/seed_readme_screenshots.exs", __DIR__)
