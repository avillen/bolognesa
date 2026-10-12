# Roadmap

This roadmap describes priorities and possibilities, not a release schedule or promise to implement every idea. See [status](status.md) for current implementation and verification evidence.

## Near-term focus

The application has the main home-media flows in place. The next useful work is to improve confidence in those flows through real use and focused contributions:

- Make local setup easy to follow on common Docker and Linux environments.
- Check scanning and inspection recovery, repeated scans, and failure feedback.
- Verify that manual identification corrections survive later work.
- Test authenticated playback controls, formats, and performance on different browsers and devices.
- Keep the application responsive on modest hardware and improve accessibility and documentation as friction is found.

These are areas to investigate and improve; current verification limits are listed in [status](status.md).

## Possible later directions

Music, additional user accounts, general remote access, and dedicated clients may make sense if people need them and someone can maintain them. Discuss the problem and a small first step before starting substantial work. Their appearance here does not mean they are scheduled or accepted.

Series support is implemented in the codebase. A file containing multiple episodes is played in full from its beginning; the application does not cut it into episodes or automatically advance playback.

## Working on a roadmap item

Before implementation, check current code, the relevant [decisions](decisions/README.md), and [conventions](conventions/). Discuss substantial features first. Keep temporary design or implementation notes with the change that uses them, then remove them or distill lasting information into a convention or decision. Update [status](status.md) with verified results and remaining work.
