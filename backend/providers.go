package main

import (
	"context"
	"fmt"
	"os"
)

type LLMProvider interface {
	GenerateResponse(ctx context.Context, prompt string, stream chan<- string) error
	GenerateImage(ctx context.Context, prompt string) (string, error)
}

type OpenAIProvider struct {
	APIKey string
}

func (p *OpenAIProvider) GenerateResponse(ctx context.Context, prompt string, stream chan<- string) error {
	defer close(stream)
	// Placeholder for actual OpenAI SSE implementation
	stream <- "OpenAI: Ich analysiere deine Anfrage... "
	stream <- "Hier ist eine Antwort von GPT-4o basierend auf deinem Prompt: " + prompt
	return nil
}

func (p *OpenAIProvider) GenerateImage(ctx context.Context, prompt string) (string, error) {
	// Placeholder for DALL-E integration
	return "https://image-url-from-dalle.com/placeholder.png", nil
}

type GeminiProvider struct {
	APIKey string
}

func (p *GeminiProvider) GenerateResponse(ctx context.Context, prompt string, stream chan<- string) error {
	defer close(stream)
	// Placeholder for actual Gemini streaming implementation
	stream <- "Gemini: Ich durchsuche das Web... "
	stream <- "Basierend auf Google Gemini 1.5 Pro: " + prompt
	return nil
}

func (p *GeminiProvider) GenerateImage(ctx context.Context, prompt string) (string, error) {
	return "", fmt.Errorf("Gemini image generation not implemented in this version")
}

func GetProvider(modelName string) LLMProvider {
	if modelName == "gpt-4o" {
		return &OpenAIProvider{APIKey: os.Getenv("OPENAI_API_KEY")}
	}
	return &GeminiProvider{APIKey: os.Getenv("GEMINI_API_KEY")}
}
