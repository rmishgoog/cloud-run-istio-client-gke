// Sample run-helloworld is a minimal Cloud Run service.
package main

import (
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

type person struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	City    string `json:"city"`
	State   string `json:"state"`
	Zipcode int    `json:"zip"`
}

var persons = []person{
	{ID: "1", Name: "Nathan Daniels", City: "Plainfield", State: "IL", Zipcode: 60490},
	{ID: "2", Name: "James Baldwin", City: "Naperville", State: "IL", Zipcode: 60540},
	{ID: "3", Name: "Rachel Brown", City: "Bolingbrook", State: "IL", Zipcode: 60440},
}

func getPersons(c *gin.Context) {
	c.IndentedJSON(http.StatusOK, persons)
}

func addPerson(c *gin.Context) {
	var newPerson person
	if err := c.BindJSON(&newPerson); err != nil {
		return
	}
	persons = append(persons, newPerson)
	c.IndentedJSON(http.StatusCreated, newPerson)
}

func main() {
	gin.SetMode(gin.ReleaseMode)
	router := gin.Default()
	router.GET("/persons", getPersons)
	router.POST("/persons", addPerson)
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("main.go: defaulting to port %s", port)
	}
	log.Printf("listening on port %s", port)
	router.Run(":" + port + "")
}
