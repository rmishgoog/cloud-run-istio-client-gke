package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"google.golang.org/api/idtoken"
)

/*This was tested by running the two services locally and works well.
However, the real backend for the front-end application will be the envoy proxy.*/
func getDetails(w http.ResponseWriter, req *http.Request) {
	resp, err := http.Get("http://localhost:8080/persons")
	if err != nil {
		error := fmt.Errorf("main.go: An error when calling the back-end api %s", err)
		fmt.Println(error)
	}
	defer resp.Body.Close()
	if _, err := io.Copy(w, resp.Body); err != nil {
		error := fmt.Errorf("main.go: An error occurred when reading the response body %s", err)
		fmt.Println(error)
	}
}

func getPersons(w http.ResponseWriter, req *http.Request) {
	ctx := context.Background()
	audience := os.Getenv("BACKEND_AUDIENCE_URL")
	target_url := os.Getenv("BACKEND_TARGET_URL")
	client, err := idtoken.NewClient(ctx, audience)
	if err != nil {
		error := fmt.Errorf("main.go:front-end-app:idtoken.NewClient: %v", err)
		log.Println(error)
	}

	resp, err := client.Get(target_url)
	if err != nil {
		error := fmt.Errorf("main.go:front-end-app:client.Get: %v", err)
		log.Println(error)
	}
	defer resp.Body.Close()
	if _, err := io.Copy(w, resp.Body); err != nil {
		error := fmt.Errorf("main.go:front-end-app:io.Copy: %v", err)
		log.Println(error)
	}
}

func main() {
	http.HandleFunc("/locals", getDetails)
	http.HandleFunc("/persons", getPersons)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("main.go:front-end-app:defaulting to port %s", port)
	}
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
