# Project Overview
A cross-platform application (iOS, iPadOS, Windows Desktop) that turns children's picture books (PDFs or images) into immersive, multi-character audiobooks using Vision-Language Models (VLM), LLMs, and Text-to-Speech (TTS).

# Core Workflow
1. **Input:** User uploads images or a PDF of a children's book.
2. **Vision Analysis:** A VLM parses the pages, extracts text, or generates a cohesive story based on the illustrations.
3. **Translation & Role Assignment:** The user selects a target language for playback. An LLM analyzes the extracted text/story, translates it into the chosen language (if different from the source), identifies characters, extracts traits, and formats the output into a JSON script.
4. **Audio Generation:** A multi-lingual TTS engine generates distinct, emotionally expressive voices for each character and the narrator based on the translated text in the JSON script.
5. **Playback:** Audio clips are stitched together and played back with seamless transitions.

# Development Phases

## Phase 1: Technology Stack Proposal (Current Step)
Before writing any code, propose the optimal tech stack. 
Requirements:
- **Frontend:** Single or highly shared codebase for iOS/iPadOS/Windows (e.g., Flutter, React Native, Tauri).
- **Backend/Proxy:** A secure way to handle VLM/LLM/TTS API calls without exposing keys on the client.
- **State/Audio:** A reliable way to handle complex audio playlists and state management.
*Action: Present your proposal to the user for approval.*

## Phase 2: Foundation & Mock UI
- Initialize the approved project structure.
- Build the file/image upload UI.
- Build a loading screen (needs to be child-friendly and engaging, as AI generation takes time).
- Create static JSON mock data simulating the LLM script output.
- Create a mock audio player interface.

## Phase 3: Backend & AI Integration
- Set up the backend proxy.
- Integrate the VLM for image-to-text/story generation.
- Integrate the LLM to output the structured JSON script. **Crucial:** The LLM prompt must instruct the model to translate the text into the user's selected language while generating the JSON (characters, traits, translated dialogue).
- Integrate a multi-lingual TTS API (e.g., ElevenLabs, Azure Neural TTS) to generate audio files, ensuring the chosen voice models support the user's selected language.

## Phase 4: Audio Stitching & Polish
- Implement the logic to sequence and play the generated audio files seamlessly.
- Add text-highlighting (karaoke style) if the TTS engine supports timestamps.
- Final UI/UX polish.