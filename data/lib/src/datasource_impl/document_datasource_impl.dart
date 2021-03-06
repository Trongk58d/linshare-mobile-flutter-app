// LinShare is an open source filesharing software, part of the LinPKI software
// suite, developed by Linagora.
//
// Copyright (C) 2020 LINAGORA
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU Affero General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later version,
// provided you comply with the Additional Terms applicable for LinShare software by
// Linagora pursuant to Section 7 of the GNU Affero General Public License,
// subsections (b), (c), and (e), pursuant to which you must notably (i) retain the
// display in the interface of the “LinShare™” trademark/logo, the "Libre & Free" mention,
// the words “You are using the Free and Open Source version of LinShare™, powered by
// Linagora © 2009–2020. Contribute to Linshare R&D by subscribing to an Enterprise
// offer!”. You must also retain the latter notice in all asynchronous messages such as
// e-mails sent with the Program, (ii) retain all hypertext links between LinShare and
// http://www.linshare.org, between linagora.com and Linagora, and (iii) refrain from
// infringing Linagora intellectual property rights over its trademarks and commercial
// brands. Other Additional Terms apply, see
// <http://www.linshare.org/licenses/LinShare-License_AfferoGPL-v3.pdf>
// for more details.
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
// more details.
// You should have received a copy of the GNU Affero General Public License and its
// applicable Additional Terms for LinShare along with this program. If not, see
// <http://www.gnu.org/licenses/> for the GNU Affero General Public License version
//  3 and <http://www.linshare.org/licenses/LinShare-License_AfferoGPL-v3.pdf> for
//  the Additional Terms applicable to LinShare software.

import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:data/src/datasource/document_datasource.dart';
import 'package:data/src/extensions/uri_extension.dart';
import 'package:data/src/network/config/endpoint.dart';
import 'package:data/src/network/linshare_http_client.dart';
import 'package:data/src/network/model/response/document_response.dart';
import 'package:data/src/network/remote_exception_thrower.dart';
import 'package:data/src/util/constant.dart';
import 'package:dio/dio.dart';
import 'package:domain/domain.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_uploader/flutter_uploader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:data/src/network/model/response/document_response.dart';
import 'package:flutter_downloader/flutter_downloader.dart';

class DocumentDataSourceImpl implements DocumentDataSource {
  final FlutterUploader _uploader;
  final LinShareHttpClient _linShareHttpClient;
  final RemoteExceptionThrower _remoteExceptionThrower;

  DocumentDataSourceImpl(this._uploader, this._linShareHttpClient, this._remoteExceptionThrower);

  @override
  Future<FileUploadState> upload(FileInfo fileInfo, Token token, Uri baseUrl) async {
    final file = File(fileInfo.filePath + fileInfo.fileName);
    final taskId = await _uploader.enqueue(
        url: baseUrl.withServicePath(Endpoint.documents),
        files: [
          FileItem(savedDir: fileInfo.filePath, filename: fileInfo.fileName)
        ],
        headers: {
          Constant.authorization: 'Bearer ${token.token}'
        },
        data: {
          Constant.fileSizeDataForm: (await file.length()).toString()
        });

    final mergedStream = Rx.merge([_uploader.result, _uploader.progress]).map<Either<Failure, Success>>((event) {
      if (event is UploadTaskResponse) {
        if (event.statusCode == 200) {
          return Right(FileUploadSuccess());
        }
        return Left(FileUploadFailure());
      } else if (event is UploadTaskProgress) {
        return Right(FileUploadProgress(event.progress));
      } else {
        return Left(FileUploadFailure());
      }
    });

    return FileUploadState(mergedStream, UploadTaskId(taskId));
  }

  @override
  Future<List<Document>> getAll() async {
    return Future.sync(() async {
      final documentResponseList = await _linShareHttpClient.getAllDocument();
      return documentResponseList.map((documentResponse) => documentResponse.toDocument()).toList();
    }).catchError((error) {
      _remoteExceptionThrower.throwRemoteException(error, handler: (DioError error) {
        if (error.response.statusCode == 404) {
          throw DocumentNotFound();
        } else {
          throw UnknownError(error.response.statusMessage);
        }
      });
    });
  }

  @override
  Future<DownloadTaskId> downloadDocument(DocumentId documentId, Token token, Uri baseUrl) async {
    var externalStorageDirPath;
    if (Platform.isAndroid) {
      externalStorageDirPath = (await getExternalStorageDirectory()).absolute.path;
    } else if (Platform.isIOS) {
      externalStorageDirPath = (await getApplicationDocumentsDirectory()).absolute.path;
    } else {
      throw DeviceNotSupportedException();
    }

    final taskId = await FlutterDownloader.enqueue(
      url: Endpoint.documents
          .downloadServicePath(documentId.uuid)
          .generateDownloadUrl(baseUrl),
      savedDir: externalStorageDirPath,
      headers: {
        Constant.authorization: 'Bearer ${token.token}'
      },
      showNotification: true,
      openFileFromNotification: true,
    );

    return DownloadTaskId(taskId);
  }
}
