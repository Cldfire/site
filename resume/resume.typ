#import "alta-typst.typ": alta, term, skill, styled-link

#alta(
  name: "Jarek Samic",
  links: (
    (name: "email", link: "mailto:jarek.samic@cldfire.dev"),
    (name: "website", link: "https://cldfire.dev", display: "cldfire.dev"),
    (name: "github", link: "https://github.com/Cldfire", display: "@Cldfire"),
    (name: "mastodon", link: "https://hachyderm.io/@Cldfire", display: "@cldfire@hachyderm.io"),
    (name: "location", link: "https://maps.apple.com/?address=New%20York,%20NY,%20United%20States", display: "NYC"),
  ),
  tagline: [Software Developer passionate about building impactful systems and high-performing teams.],
  [
    == Experience

    === Senior Developer \
    _1Password_\
    #term[Sep 2020 --- Present][Remote]

    - Key contributor towards passkey support across all major browsers in the 1Password browser extension.
    - Worked on high-impact CI improvements with a cross-functional team, resulting in a 50% and 60% reduction to p50 and p90 merge request pipeline times (respectively).
    - Led the build & release process for the 1Password browser extension. Overhauled the existing system to ensure predictability and implement automated nightly releases.
    - Owned the implementation & launch of Unlock with SSO in the 1Password browser extension. Collaborated with other teams to build interop between the extension and other clients.
    - Key contributor towards the 1Password browser extension for iOS. Rebuilt many aspects of the desktop extension in less than 90 days in order to launch day-one on the App Store.
    - Accelerated developers & teams across the company by sharing knowledge and providing guidance/mentoring on a day-to-day basis.
    - Built well-received internal tools and valuable testing frameworks.
    - Conducted interviews for several developer roles, contributing to the hiring of multiple people across different teams.

    === Intern \
    _1Password_\
    #term[Summer 2020][Remote]

    - Worked with Rust and Typescript to improve autofilling data into websites across our browser extension and desktop app products.
    - Heavy focus on automated testing and graceful degredation of accuracy when faced with poorly designed pages.

    === Student Developer \
    _Google Summer of Code with FFmpeg_\
    #term[Summer 2019][Remote]

    Worked independently to research, design, and implement a hardware-accelerated, single-pass video stabilization filter for the FFmpeg library. #styled-link("https://cldfire.dev/blog/gsoc-2019")[https://cldfire.dev/blog/gsoc-2019]
    
    #colbreak()
    == Projects

    ==== nvml-wrapper #styled-link("https://github.com/Cldfire/nvml-wrapper")[github]

    A safe and ergonomic Rust wrapper for the NVIDIA Management Library (NVML). Used in production by Twitter and other companies.

    ==== minecraft-status #styled-link("https://github.com/Cldfire/minecraft-status")[github]

    An iOS app with widgets that display the results of pinging a Minecraft server, supporting both Java and Bedrock editions. Rust business logic with SwiftUI frontend.

    ==== mc-server-wrapper #styled-link("https://github.com/Cldfire/mc-server-wrapper")[github]

    Lightweight Minecraft server wrapper binary that provides a Discord chat bridge and other features for vanilla servers.

    ==== actualbudget/actual #styled-link("https://github.com/actualbudget/actual")[github]

    Ported an old, complex React Native component to the web, unlocking mobile transaction entry for the popular local-first personal finance app Actual. PR: #styled-link("https://github.com/actualbudget/actual/pull/1340")[\#1340]

    ==== rust-lang/rust #styled-link("https://github.com/rust-lang/rust")[github]

    Implemented the Ayu theme for rustdoc: #styled-link("https://github.com/rust-lang/rust/pull/71237")[\#71237]

    == Education

    ==== University of Akron \
    #term[2016 --- 2020][Akron, OH]

    - B.S. in Computer Science with a minor in Mathematics — *3.9 GPA*
    - Dean's List, President's List
    - Completed 4/5 of degree and then left to accept a job offer

    == Other

    ==== Lightning Talk at Programming Conference \
    _Rust Belt Rust_\
    #term[2017][Columbus, OH]

    Gave impromptu talk about my work theming various sites in the Rust community. #styled-link("https://youtu.be/7VulqInDO6Y")[https://youtu.be/7VulqInDO6Y]

    == Skills

    Rust, Typescript, Javascript, FFI, Swift, React, SwiftUI, C, C++, native messaging, Git, CI, teamwork, debugging, problem-solving, and a love of asking _why_.
  ],
)
