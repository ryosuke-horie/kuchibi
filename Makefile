PROJECT = Kuchibi.xcodeproj
SCHEME  = Kuchibi
APP     = Kuchibi.app
DERIVED = $(HOME)/Library/Developer/Xcode/DerivedData
INSTALL_DIR = /Applications

# DerivedDataからビルド済みアプリを検索
BUILT_APP = $(shell find "$(DERIVED)" -name "$(APP)" -path "*/Debug/$(APP)" 2>/dev/null | head -1)

.PHONY: build install run clean

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
