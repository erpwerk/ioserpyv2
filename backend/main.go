package main

import (
	"log"
	"os"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/joho/godotenv"
)

func main() {
	// Load environment variables
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, using system environment variables")
	}

	app := fiber.New(fiber.Config{
		AppName: "ERPY V2 Backend",
	})

	// Middleware
	app.Use(logger.New())
	app.Use(cors.New())

	// Health check
	app.Get("/health", func(c *fiber.Ctx) error {
		return c.SendString("OK")
	})

	// Chat streaming endpoint (SSE)
	app.Get("/api/chat/stream", func(c *fiber.Ctx) error {
		model := c.Query("model", "gpt-4o")
		prompt := c.Query("prompt", "")

		c.Set("Content-Type", "text/event-stream")
		c.Set("Cache-Control", "no-cache")
		c.Set("Connection", "keep-alive")
		c.Set("Transfer-Encoding", "chunked")

		provider := GetProvider(model)
		stream := make(chan string)

		go provider.GenerateResponse(c.Context(), prompt, stream)

		c.Context().SetBodyStreamWriter(func(w *fiber.Writer) {
			for msg := range stream {
				fmt.Fprintf(w, "data: %s\n\n", msg)
				w.Flush()
			}
		})

		return nil
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Fatal(app.Listen(":" + port))
}
