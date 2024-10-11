package main

import (
	"archive/tar"
	"bufio"
	"bytes"
	"compress/gzip"
	"crypto/hmac"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

type PrePlanPayload struct {
	PayloadVersion                  int    `json:"payload_version"`
	AccessToken                     string `json:"access_token"`
	Stage                           string `json:"stage"`
	IsSpeculative                   bool   `json:"is_speculative"`
	TaskResultID                    string `json:"task_result_id"`
	TaskResultEnforcementLevel      string `json:"task_result_enforcement_level"`
	TaskResultCallbackURL           string `json:"task_result_callback_url"`
	RunAppURL                       string `json:"run_app_url"`
	RunID                           string `json:"run_id"`
	RunMessage                      string `json:"run_message"`
	RunCreatedAt                    string `json:"run_created_at"`
	RunCreatedBy                    string `json:"run_created_by"`
	WorkspaceID                     string `json:"workspace_id"`
	WorkspaceName                   string `json:"workspace_name"`
	WorkspaceAppURL                 string `json:"workspace_app_url"`
	OrganizationName                string `json:"organization_name"`
	VCSRepoURL                      string `json:"vcs_repo_url"`
	VCSBranch                       string `json:"vcs_branch"`
	VCSPullRequestURL               string `json:"vcs_pull_request_url"`
	VCSCommitURL                    string `json:"vcs_commit_url"`
	ConfigurationVersionID          string `json:"configuration_version_id"`
	ConfigurationVersionDownloadURL string `json:"configuration_version_download_url"`
	WorkspaceWorkingDirectory       string `json:"workspace_working_directory"`
}

type Result struct {
	Data ResultData `json:"data"`
}

type ResultData struct {
	Type       string           `json:"type"`
	Attributes ResultAttributes `json:"attributes"`
}

type ResultAttributes struct {
	Status  string `json:"status"`
	Message string `json:"message,omitempty"`
	URL     string `json:"url,omitempty"`
}

var jobQueue = make(chan PrePlanPayload, 100)
var hmacKey []byte

const (
	BaseDir = "/app"
)

var BaseURL string

func init() {
	// Load HMAC key from environment variable
	hmacKeyStr := os.Getenv("HMAC_KEY")
	if hmacKeyStr == "" {
		log.Println("Warning: HMAC_KEY not set. Running without HMAC verification.")
	} else {
		hmacKey = []byte(hmacKeyStr)
	}
}

func verifyHMAC(body []byte, signature string) bool {
	if len(hmacKey) == 0 {
		return true // Skip verification if HMAC key is not set
	}

	h := hmac.New(sha512.New, hmacKey)
	h.Write(body)
	expectedSignature := hex.EncodeToString(h.Sum(nil))

	return hmac.Equal([]byte(signature), []byte(expectedSignature))
}

func getPublicIP() (string, error) {
	resp, err := http.Get("https://ipv4.icanhazip.com")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	ip, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return strings.TrimSpace(string(ip)), nil
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	signature := r.Header.Get("X-TFC-Task-Signature")
	if !verifyHMAC(body, signature) {
		http.Error(w, "Invalid signature", http.StatusUnauthorized)
		return
	}

	var payload PrePlanPayload
	err = json.Unmarshal(body, &payload)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		log.Println(err.Error())
		return
	}

	jobQueue <- payload

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("200 OK"))
}

func main() {
	BaseURL = os.Getenv("BASE_URL")
	if BaseURL == "" {
		publicIP, err := getPublicIP()
		if err != nil {
			log.Printf("Failed to get public IP: %v. Using localhost as fallback.", err)
			BaseURL = "http://localhost"
		} else {
			BaseURL = fmt.Sprintf("http://%s", publicIP)
		}
	}

	log.Printf("Using BaseURL: %s", BaseURL)

	go processJobs()

	http.HandleFunc("/", handleRequest)
	http.HandleFunc("/runs/", handleRunInfo)

	log.Println("Server listening on port 80...")
	log.Fatal(http.ListenAndServe(":80", nil))
}

func downloadConfigVersion(url, token, runID string) error {
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return err
	}

	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/vnd.api+json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("request failed with status code: %d", resp.StatusCode)
	}

	runDir := filepath.Join(BaseDir, runID)
	err = os.MkdirAll(runDir, os.ModePerm)
	if err != nil {
		return err
	}

	tarGzFile := filepath.Join(runDir, "config.tar.gz")
	tempFile, err := os.Create(tarGzFile)
	if err != nil {
		return err
	}
	defer tempFile.Close()

	_, err = io.Copy(tempFile, resp.Body)
	if err != nil {
		return err
	}

	log.Println("Download OK")

	err = extractTarGz(tarGzFile, runDir)
	if err != nil {
		return err
	}
	log.Println("File extracted OK")

	return nil
}

func extractTarGz(tarGzFile, destination string) error {
	file, err := os.Open(tarGzFile)
	if err != nil {
		return err
	}
	defer file.Close()

	gzipReader, err := gzip.NewReader(file)
	if err != nil {
		return err
	}
	defer gzipReader.Close()

	tarReader := tar.NewReader(gzipReader)

	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}

		target := filepath.Join(destination, header.Name)

		switch header.Typeflag {
		case tar.TypeDir:
			err = os.MkdirAll(target, os.ModePerm)
			if err != nil {
				return err
			}

		case tar.TypeReg:
			err = os.MkdirAll(filepath.Dir(target), os.ModePerm)
			if err != nil {
				return err
			}

			file, err := os.Create(target)
			if err != nil {
				return err
			}
			defer file.Close()

			if _, err := io.Copy(file, tarReader); err != nil {
				return err
			}

		default:
			return fmt.Errorf("unsupported file type: %v in %s", header.Typeflag, header.Name)
		}
	}

	return nil
}

func sendPatchRequest(url string, payload []byte, authToken string) error {
	req, err := http.NewRequest(http.MethodPatch, url, bytes.NewBuffer(payload))
	if err != nil {
		return err
	}

	req.Header.Set("Content-Type", "application/vnd.api+json")
	req.Header.Set("Authorization", "Bearer "+authToken)

	client := http.DefaultClient
	resp, err := client.Do(req)
	if err != nil || resp == nil {
		return err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	respBodyStr := string(respBody)

	if resp.StatusCode != http.StatusOK {
		log.Println(respBodyStr)
		return fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	return nil
}

func processJobs() {
	for payload := range jobQueue {
		log.Printf("Processing job: %+v\n", payload.RunID)

		runDir := filepath.Join(BaseDir, payload.RunID)

		err := downloadConfigVersion(payload.ConfigurationVersionDownloadURL, payload.AccessToken, payload.RunID)
		if err != nil {
			log.Println(err.Error())
			continue
		}

		// Generate Terraform graph
		graphFile := filepath.Join(runDir, "graph.png")
		err = generateTerraformGraph(runDir, graphFile)
		if err != nil {
			log.Printf("Error generating Terraform graph: %v", err)
		}

		patternsFile := filepath.Join(BaseDir, "patternsFile.txt")
		patterns, err := readRegexPatterns(patternsFile)
		if err != nil {
			log.Println(err.Error())
			continue
		}

		matchCounts := runRegexOnFolder(runDir, patterns)

		var result Result
		if len(matchCounts) > 0 && err == nil {
			var message strings.Builder
			for pattern, count := range matchCounts {
				if count > 0 {
					message.WriteString(fmt.Sprintf("Pattern: %s, Matches: %d\n", pattern, count))
				}
			}

			log.Println(message.String())
			result = createFailedResult(message.String(), payload.RunID)
		} else {
			result = createPassedResult("Configured patterns not found", payload.RunID)
		}

		jsonData, err := json.Marshal(result)
		if err != nil {
			log.Println(err.Error())
			continue
		}

		err = sendPatchRequest(payload.TaskResultCallbackURL, jsonData, payload.AccessToken)
		if err != nil {
			log.Println(err.Error())
		}

		time.Sleep(1 * time.Second)
	}
}

func generateTerraformGraph(runDir, outputFile string) error {
	// Construct the path to the tf/demo_server directory
	tfDir := filepath.Join(runDir, "tf", "demo_server")

	// Check if the directory exists
	if _, err := os.Stat(tfDir); os.IsNotExist(err) {
		return fmt.Errorf("tf/demo_server directory not found in %s", runDir)
	}

	// Change to the tf/demo_server directory
	err := os.Chdir(tfDir)
	if err != nil {
		return fmt.Errorf("error changing to tf/demo_server directory: %v", err)
	}

	// Run terraform init
	initCmd := exec.Command("terraform", "init")
	initCmd.Dir = tfDir
	err = initCmd.Run()
	if err != nil {
		return fmt.Errorf("error running terraform init: %v", err)
	}

	// Run terraform graph
	cmd := exec.Command("terraform", "graph")
	cmd.Dir = tfDir

	dotOutput, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("error running terraform graph: %v", err)
	}

	// Generate PNG from DOT output
	dotCmd := exec.Command("dot", "-Tpng", "-o", outputFile)
	dotCmd.Stdin = bytes.NewReader(dotOutput)
	dotCmd.Dir = tfDir

	err = dotCmd.Run()
	if err != nil {
		return fmt.Errorf("error generating PNG from DOT: %v", err)
	}

	return nil
}

func createPassedResult(message string, runID string) Result {
	return Result{
		Data: ResultData{
			Type: "task-results",
			Attributes: ResultAttributes{
				Status:  "passed",
				Message: message,
				URL:     fmt.Sprintf("%s/runs/%s", BaseURL, runID),
			},
		},
	}
}

func createFailedResult(message string, runID string) Result {
	return Result{
		Data: ResultData{
			Type: "task-results",
			Attributes: ResultAttributes{
				Status:  "failed",
				Message: message,
				URL:     fmt.Sprintf("%s/runs/%s", BaseURL, runID),
			},
		},
	}
}

func runRegexOnFolder(baseDir string, regexPatterns []string) map[string]int {
	matchCounts := make(map[string]int)
	tfDir := filepath.Join(baseDir, "tf", "demo_server")

	// Check if the tf/demo_server directory exists
	if _, err := os.Stat(tfDir); os.IsNotExist(err) {
		log.Printf("tf/demo_server directory not found in %s", baseDir)
		return matchCounts
	}

	err := filepath.Walk(tfDir, func(filePath string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if info.IsDir() {
			return nil
		}

		content, err := os.ReadFile(filePath)
		if err != nil {
			return err
		}

		for _, pattern := range regexPatterns {
			regex, err := regexp.Compile(pattern)
			if err != nil {
				log.Printf("Error compiling regex pattern: %s\n", pattern)
				continue
			}

			matches := regex.FindAll(content, -1)
			if matches != nil {
				matchCounts[pattern] += len(matches)
			}
		}

		return nil
	})

	if err != nil {
		log.Printf("Error walking through folder: %v", err)
	}

	return matchCounts
}

func readRegexPatterns(filePath string) ([]string, error) {
	patterns := []string{}

	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		pattern := scanner.Text()
		patterns = append(patterns, pattern)
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return patterns, nil
}

func handleRunInfo(w http.ResponseWriter, r *http.Request) {
	runID := r.URL.Path[len("/runs/"):]
	runDir := filepath.Join(BaseDir, runID)

	// Check if the graph.png file exists
	graphFile := filepath.Join(runDir, "graph.png")
	if _, err := os.Stat(graphFile); os.IsNotExist(err) {
		http.Error(w, "Graph not found", http.StatusNotFound)
		return
	}

	// Serve the graph.png file
	http.ServeFile(w, r, graphFile)
}
