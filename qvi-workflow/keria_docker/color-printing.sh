#!/bin/bash

# Utility functions
print_green() {
  text="$1"
  printf "\e[32m%s\e[0m\n" "$text"
}

print_yellow(){
  text="$1"
  printf "\e[33m%s\e[0m\n" "$text"
}

print_red() {
  text="$1"
  printf "\e[31m%s\e[0m\n" "$text"
}

print_lcyan() {
  text="$1"
  printf "\e[96m%s\e[0m\n" "$text"
}

print_bg_blue() {
  text="$1"
  printf "\e[44m%s\e[0m\n" "$text"
}

print_dark_gray() {
  text="$1"
  printf "\e[90m%s\e[0m\n" "$text"
}