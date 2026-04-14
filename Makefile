PROJECT = Kuchibi.xcodeproj
SCHEME  = Kuchibi
APP     = Kuchibi.app
DERIVED = $(HOME)/Library/Developer/Xcode/DerivedData
INSTALL_DIR = /Applications

# DerivedDataからビルド済みアプリを検索
BUILT_APP = $(shell find "$(DERIVED)" -name "$(APP)" -path "*/Debug/$(APP)" 2>/dev/null | head -1)

# Kotoba-Whisper Bilingual v1.0 モデル配置先
MODELS_DIR = $(HOME)/Library/Application Support/Kuchibi/models
KOTOBA_REPO = https://huggingface.co/kotoba-tech/kotoba-whisper-bilingual-v1.0-ggml/resolve/main
KOTOBA_Q5 = ggml-kotoba-whisper-bilingual-v1.0-q5_0.bin
KOTOBA_FULL = ggml-kotoba-whisper-bilingual-v1.0.bin

.PHONY: build install run clean fetch-models fetch-kotoba-q5 fetch-kotoba-full

## ビルドして /Applications にインストールする（デフォルト）
all: build install

## Xcodeでビルド
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build | xcpretty 2>/dev/null || xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

## ビルド済みアプリを /Applications にインストール（rsync で TCC 権限を維持）
install:
	@if [ -z "$(BUILT_APP)" ]; then echo "ビルド済みアプリが見つかりません。先に make build を実行してください"; exit 1; fi
	@echo "インストール中: $(BUILT_APP) → $(INSTALL_DIR)/$(APP)"
	@pkill -x Kuchibi 2>/dev/null || true
	@sleep 0.5
	@rsync -a --delete "$(BUILT_APP)/" "$(INSTALL_DIR)/$(APP)/"
	@codesign --force --sign - \
		--identifier com.kuchibi.app \
		--preserve-metadata=entitlements,requirements,flags,runtime \
		"$(INSTALL_DIR)/$(APP)"
	@echo "インストール完了"
	@echo "NOTE: make run を 2 回連続実行し、2 回目以降の起動でアクセシビリティ権限ダイアログが出ないことを確認してください"

## インストール後に起動
run: install
	open "$(INSTALL_DIR)/$(APP)"

## DerivedDataのビルドキャッシュを削除
clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean

## Kotoba-Whisper Bilingual v1.0 モデルファイル（Q5 + Full）をダウンロード
fetch-models: fetch-kotoba-q5 fetch-kotoba-full
	@echo "モデル配置完了: $(MODELS_DIR)"
	@ls -lh "$(MODELS_DIR)" | grep -E "ggml-kotoba" || true

## Kotoba v1Q5（軽量量子化版、約 500MB）
fetch-kotoba-q5:
	@mkdir -p "$(MODELS_DIR)"
	@if [ -f "$(MODELS_DIR)/$(KOTOBA_Q5)" ]; then \
		echo "既に配置済み: $(MODELS_DIR)/$(KOTOBA_Q5)"; \
	else \
		echo "ダウンロード中: $(KOTOBA_Q5)"; \
		curl -L --fail --progress-bar -o "$(MODELS_DIR)/$(KOTOBA_Q5)" "$(KOTOBA_REPO)/$(KOTOBA_Q5)"; \
	fi

## Kotoba v1 Full（非量子化版、約 1.5GB）
fetch-kotoba-full:
	@mkdir -p "$(MODELS_DIR)"
	@if [ -f "$(MODELS_DIR)/$(KOTOBA_FULL)" ]; then \
		echo "既に配置済み: $(MODELS_DIR)/$(KOTOBA_FULL)"; \
	else \
		echo "ダウンロード中: $(KOTOBA_FULL)"; \
		curl -L --fail --progress-bar -o "$(MODELS_DIR)/$(KOTOBA_FULL)" "$(KOTOBA_REPO)/$(KOTOBA_FULL)"; \
	fi
